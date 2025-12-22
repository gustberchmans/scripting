<#
.SYNOPSIS
  This script periodically checks a MySQL database for new invoices, transforms them
  from XML to HTML using an XSLT file, and then converts them to PDF.
.DESCRIPTION
  The script is designed to run in a Docker container. It reads database configuration
  from environment variables. It processes invoices with the 'new' status and updates
  their status to 'processed' or 'error'.

  Required PowerShell Modules:
  - SimplySql
  - iText 7 (DLLs loaded from /app/lib)
#>

# --- Configuration ---
$dbHost = $env:DB_HOST
$dbUser = $env:DB_USER
$dbPassword = $env:DB_PASSWORD
$dbDatabase = $env:DB_DATABASE
$connectionName = "InvoicesDB"

$xsltPath = "/app/templates/invoice-transform.xslt"
$outputDir = "/app/output"
$pollingIntervalSeconds = 30

# --- Dependency Check ---
# Dependencies (SimplySql, iText) are installed via Dockerfile.

# --- Function Definitions ---

function Update-InvoiceStatus {
    param($invoiceId, $status, $errorMessage = $null)
    
    Write-Host "Updating invoice ID $invoiceId to status '$status'."
    $query = "UPDATE invoices SET status = '$status', processed_at = NOW()"
    if ($errorMessage) {
        # Sanitize error message for SQL
        $sanitizedError = $errorMessage.Replace("'", "''")
        $query += ", error_message = '$sanitizedError'"
    }
    $query += " WHERE id = $invoiceId;"
    
    Invoke-SqlUpdate -Query $query -ConnectionName $connectionName -ErrorAction Stop
}

function Transform-XmlToHtml {
    param(
        [string]$xmlContent,
        [string]$xsltPath
    )
    
    $xslt = New-Object System.Xml.Xsl.XslCompiledTransform;
    $xslt.Load($xsltPath)

    $xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xmlContent))
    
    $stringWriter = New-Object System.IO.StringWriter
    $xslt.Transform($xmlReader, $null, $stringWriter)
    
    return $stringWriter.ToString()
}

function Test-InvoiceTotals {
    param(
        [xml]$xmlDoc
    )
    
    # Define namespaces for XPath
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
    $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')
    
    # Get the declared total from LegalMonetaryTotal
    $declaredTotalNode = $xmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:LineExtensionAmount", $ns)
    if (-not $declaredTotalNode) { return $false } # No total found, invalid
    $declaredTotal = [decimal]$declaredTotalNode.'#text'
    
    # Calculate the sum of all invoice lines
    $lineItems = $xmlDoc.SelectNodes("//cac:InvoiceLine/cbc:LineExtensionAmount", $ns)
    $calculatedTotal = 0.0
    foreach ($item in $lineItems) {
        $calculatedTotal += [decimal]$item.'#text'
    }
    
    Write-Host "Validation: Declared Total = $declaredTotal, Calculated Total = $calculatedTotal"
    
    # Compare the totals
    return $declaredTotal -eq $calculatedTotal
}

# --- Main Processing Loop ---

# Load iText Dependencies
try {
    $libPath = "/app/lib"
    $dlls = @(
        "BouncyCastle.Crypto.dll",
        "Common.Logging.Core.dll",
        "Common.Logging.dll",
        "System.Drawing.Common.dll",
        "Microsoft.DotNet.PlatformAbstractions.dll",
        "Microsoft.Extensions.DependencyModel.dll",
        "itext.io.dll",
        "itext.kernel.dll",
        "itext.layout.dll",
        "itext.forms.dll",
        "itext.pdfa.dll",
        "itext.sign.dll",
        "itext.styledxmlparser.dll",
        "itext.svg.dll",
        "itext.barcodes.dll",
        "itext.html2pdf.dll"
    )
    foreach ($dll in $dlls) { Add-Type -Path (Join-Path $libPath $dll) }
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
} catch {
    Write-Host "FATAL: Could not load iText dependencies. Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Connect-Database {
    try {
        # Close existing connection if any to ensure a clean state
        try { Close-SqlConnection -ConnectionName $connectionName -ErrorAction Stop } catch {}

        $secPass = ConvertTo-SecureString $dbPassword -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($dbUser, $secPass)
        
        # Connect without specifying a database first to ensure we can create it if missing
        Open-MySqlConnection -Server $dbHost -Credential $cred -ConnectionName $connectionName -ErrorAction Stop
        
        # Ensure Database and Schema exist (Self-healing)
        Invoke-SqlUpdate -Query "CREATE DATABASE IF NOT EXISTS $dbDatabase;" -ConnectionName $connectionName -ErrorAction Stop
        Invoke-SqlUpdate -Query "USE $dbDatabase;" -ConnectionName $connectionName -ErrorAction Stop
        
        $tableQuery = @"
CREATE TABLE IF NOT EXISTS invoices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    peppol_xml LONGTEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'new',
    processed_at DATETIME NULL,
    error_message TEXT NULL
);
"@
        Invoke-SqlUpdate -Query $tableQuery -ConnectionName $connectionName -ErrorAction Stop

        # Insert sample data if table is empty
        $count = Invoke-SqlQuery -Query "SELECT COUNT(*) AS c FROM invoices" -ConnectionName $connectionName -ErrorAction Stop
        if ($count.c -eq 0) {
            $sampleXml = '<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"><cbc:ID>INV-DEMO-001</cbc:ID><cbc:IssueDate>2023-12-22</cbc:IssueDate><cbc:DueDate>2024-01-22</cbc:DueDate><cac:AccountingSupplierParty><cac:Party><cac:PartyName><cbc:Name>Test Supplier Inc.</cbc:Name></cac:PartyName></cac:Party></cac:AccountingSupplierParty><cac:AccountingCustomerParty><cac:Party><cac:PartyName><cbc:Name>Test Customer Ltd.</cbc:Name></cac:PartyName></cac:Party></cac:AccountingCustomerParty><cac:InvoiceLine><cbc:ID>1</cbc:ID><cbc:InvoicedQuantity unitCode="C62">1</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount><cac:Item><cbc:Name>Consulting Services</cbc:Name></cac:Item><cac:Price><cbc:PriceAmount currencyID="EUR">100.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine><cac:LegalMonetaryTotal><cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount><cbc:TaxExclusiveAmount currencyID="EUR">100.00</cbc:TaxExclusiveAmount><cbc:TaxInclusiveAmount currencyID="EUR">121.00</cbc:TaxInclusiveAmount><cbc:PayableAmount currencyID="EUR">121.00</cbc:PayableAmount></cac:LegalMonetaryTotal></Invoice>'
            Invoke-SqlUpdate -Query "INSERT INTO invoices (peppol_xml, status) VALUES ('$sampleXml', 'new')" -ConnectionName $connectionName -ErrorAction Stop
            Write-Host "Inserted sample invoice data."
        }
        
        Write-Host "Successfully connected to database '$dbDatabase' and verified schema." -ForegroundColor Green
    } catch {
        throw "Database connection failed: $($_.Exception.Message)"
    }
}

Write-Host "Invoice processing script started. Waiting for database to be ready..."
Start-Sleep -Seconds 15 # Give the database time to initialize

try {
    Import-Module SimplySql
    Connect-Database
}
catch {
    Write-Host "FATAL: Could not connect to the database. Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

while ($true) {
    try {
        $newInvoices = Invoke-SqlQuery -Query "SELECT id, peppol_xml FROM invoices WHERE status = 'new';" -ConnectionName $connectionName -ErrorAction Stop
    }
    catch {
        Write-Host "Error querying database: $($_.Exception.Message). Attempting reconnection..." -ForegroundColor Yellow
        try { Connect-Database } catch { Write-Host "Reconnection failed: $($_.Exception.Message)" }
        Start-Sleep -Seconds $pollingIntervalSeconds
        continue
    }
    
    if (-not $newInvoices) {
        Write-Host "No new invoices found. Sleeping for $pollingIntervalSeconds seconds."
    }

    foreach ($invoice in $newInvoices) {
        $invoiceId = $invoice.id
        Write-Host "Processing invoice ID: $invoiceId"
        
        try {
            # 1. Validate the invoice data
            $xmlDoc = [xml]$invoice.peppol_xml
            if (-not (Test-InvoiceTotals -xmlDoc $xmlDoc)) {
                throw "Validation failed: The sum of line items does not match the LegalMonetaryTotal."
            }

            # 2. Set status to 'processing'
            Update-InvoiceStatus -invoiceId $invoiceId -status 'processing'

            # 3. Transform XML to HTML
            $htmlContent = Transform-XmlToHtml -xmlContent $invoice.peppol_xml -xsltPath $xsltPath
            if (-not $htmlContent) {
                throw "Transformation to HTML failed or produced empty content."
            }

            # 4. Generate PDF
            $pdfPath = Join-Path -Path $outputDir -ChildPath "invoice-$($invoiceId)-$(Get-Date -Format 'yyyyMMddHHmmss').pdf"
            
            $pdfWriter = [iText.Kernel.Pdf.PdfWriter]::new($pdfPath)
            $pdfDocument = [iText.Kernel.Pdf.PdfDocument]::new($pdfWriter)
            $pdfDocument.SetDefaultPageSize([iText.Kernel.Geom.PageSize]::A4)
            $converterProperties = [iText.Html2pdf.ConverterProperties]::new()
            $converterProperties.SetBaseUri($outputDir)
            [iText.Html2Pdf.HtmlConverter]::ConvertToPdf($htmlContent, $pdfDocument, $converterProperties)
            $pdfDocument.Close()

            Write-Host "Successfully generated PDF: $pdfPath"

            # 5. Set status to 'processed'
            Update-InvoiceStatus -invoiceId $invoiceId -status 'processed'
        }
        catch {
            $errorMessage = "Failed to process invoice ID $invoiceId. Error: $($_.Exception.Message)"
            Write-Host $errorMessage -ForegroundColor Red
            Update-InvoiceStatus -invoiceId $invoiceId -status 'error' -errorMessage $errorMessage
        }
    }
    
    Start-Sleep -Seconds $pollingIntervalSeconds
}
