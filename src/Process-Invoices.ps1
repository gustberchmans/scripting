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
$pollingIntervalSeconds = 5

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

function Test-InvoiceBusinessRules {
    param(
        [xml]$xmlDoc
    )
    
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
    $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')
    
    # Validate Supplier Name
    $supplierName = $xmlDoc.SelectSingleNode("//cac:AccountingSupplierParty/cac:Party/cac:PartyName/cbc:Name", $ns)
    if (-not $supplierName -or [string]::IsNullOrWhiteSpace($supplierName.'#text')) {
        Write-Host "Validation Error: Supplier Name is missing or empty."
        return $false
    }
    if ($supplierName.'#text' -match '^\d+$') {
        Write-Host "Validation Error: Supplier Name '$($supplierName.'#text')' cannot be purely numeric."
        return $false
    }

    # Validate Customer Name
    $customerName = $xmlDoc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party/cac:PartyName/cbc:Name", $ns)
    if (-not $customerName -or [string]::IsNullOrWhiteSpace($customerName.'#text')) {
        Write-Host "Validation Error: Customer Name is missing or empty."
        return $false
    }
    if ($customerName.'#text' -match '^\d+$') {
        Write-Host "Validation Error: Customer Name '$($customerName.'#text')' cannot be purely numeric."
        return $false
    }

    return $true
}

function Convert-HtmlToPdf {
    param(
        [string]$htmlContent,
        [string]$outputPath,
        [string]$baseUri
    )
    $pdfWriter = [iText.Kernel.Pdf.PdfWriter]::new($outputPath)
    $pdfDocument = [iText.Kernel.Pdf.PdfDocument]::new($pdfWriter)
    $pdfDocument.SetDefaultPageSize([iText.Kernel.Geom.PageSize]::A4)
    $converterProperties = [iText.Html2pdf.ConverterProperties]::new()
    $converterProperties.SetBaseUri($baseUri)
    [iText.Html2Pdf.HtmlConverter]::ConvertToPdf($htmlContent, $pdfDocument, $converterProperties)
    $pdfDocument.Close()
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

        # --- MVP Requirement: Trigger and Event Handling ---
        # Create Audit Table to satisfy the requirement of creating a record on event
        $auditTableQuery = @"
CREATE TABLE IF NOT EXISTS invoice_audit (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    invoice_id INT,
    action VARCHAR(50),
    log_time DATETIME DEFAULT CURRENT_TIMESTAMP
);
"@
        Invoke-SqlUpdate -Query $auditTableQuery -ConnectionName $connectionName -ErrorAction Stop

        # Create Trigger (Drop if exists to ensure idempotency)
        Invoke-SqlUpdate -Query "DROP TRIGGER IF EXISTS after_invoice_insert;" -ConnectionName $connectionName -ErrorAction Stop
        
        $triggerQuery = @"
CREATE TRIGGER after_invoice_insert 
AFTER INSERT ON invoices
FOR EACH ROW 
INSERT INTO invoice_audit (invoice_id, action) VALUES (NEW.id, 'NEW_INVOICE_RECEIVED');
"@
        Invoke-SqlUpdate -Query $triggerQuery -ConnectionName $connectionName -ErrorAction Stop

        # Insert sample data if table is empty
        $count = Invoke-SqlQuery -Query "SELECT COUNT(*) AS c FROM invoices" -ConnectionName $connectionName -ErrorAction Stop
        if ($count.c -eq 0) {
            $sampleXml = '<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"><cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID><cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID><cbc:ID>INV-DEMO-001</cbc:ID><cbc:IssueDate>2023-12-22</cbc:IssueDate><cbc:DueDate>2024-01-22</cbc:DueDate><cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode><cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode><cbc:BuyerReference>REF-001</cbc:BuyerReference><cac:AccountingSupplierParty><cac:Party><cbc:EndpointID schemeID="0088">1234567890123</cbc:EndpointID><cac:PartyIdentification><cbc:ID>12345678</cbc:ID></cac:PartyIdentification><cac:PartyName><cbc:Name>Demo Supplier Inc.</cbc:Name></cac:PartyName><cac:PostalAddress><cbc:StreetName>Business Road 1</cbc:StreetName><cbc:CityName>Amsterdam</cbc:CityName><cbc:PostalZone>1000AA</cbc:PostalZone><cac:Country><cbc:IdentificationCode>NL</cbc:IdentificationCode></cac:Country></cac:PostalAddress><cac:PartyTaxScheme><cbc:CompanyID>NL123456789B01</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme><cac:PartyLegalEntity><cbc:RegistrationName>Demo Supplier Inc.</cbc:RegistrationName><cbc:CompanyID>12345678</cbc:CompanyID></cac:PartyLegalEntity><cac:Contact><cbc:Name>John Doe</cbc:Name><cbc:Telephone>+31201234567</cbc:Telephone><cbc:ElectronicMail>info@demosupplier.com</cbc:ElectronicMail></cac:Contact></cac:Party></cac:AccountingSupplierParty><cac:AccountingCustomerParty><cac:Party><cbc:EndpointID schemeID="0002">987654321</cbc:EndpointID><cac:PartyIdentification><cbc:ID schemeID="0002">987654321</cbc:ID></cac:PartyIdentification><cac:PartyName><cbc:Name>Test Customer Ltd.</cbc:Name></cac:PartyName><cac:PostalAddress><cbc:StreetName>Customer Lane 5</cbc:StreetName><cbc:CityName>Rotterdam</cbc:CityName><cbc:PostalZone>2000BB</cbc:PostalZone><cac:Country><cbc:IdentificationCode>NL</cbc:IdentificationCode></cac:Country></cac:PostalAddress><cac:PartyTaxScheme><cbc:CompanyID>NL987654321B01</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme><cac:PartyLegalEntity><cbc:RegistrationName>Test Customer Ltd.</cbc:RegistrationName><cbc:CompanyID schemeID="0183">987654321</cbc:CompanyID></cac:PartyLegalEntity></cac:Party></cac:AccountingCustomerParty><cac:PaymentMeans><cbc:PaymentMeansCode>30</cbc:PaymentMeansCode><cbc:PaymentID>INV-DEMO-001</cbc:PaymentID><cac:PayeeFinancialAccount><cbc:ID>NL99BANK0123456789</cbc:ID><cbc:Name>Demo Supplier Inc.</cbc:Name><cac:FinancialInstitutionBranch><cbc:ID>BANKNL2A</cbc:ID></cac:FinancialInstitutionBranch></cac:PayeeFinancialAccount></cac:PaymentMeans><cac:TaxTotal><cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount><cac:TaxSubtotal><cbc:TaxableAmount currencyID="EUR">100.00</cbc:TaxableAmount><cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount><cac:TaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>21</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:TaxCategory></cac:TaxSubtotal></cac:TaxTotal><cac:LegalMonetaryTotal><cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount><cbc:TaxExclusiveAmount currencyID="EUR">100.00</cbc:TaxExclusiveAmount><cbc:TaxInclusiveAmount currencyID="EUR">121.00</cbc:TaxInclusiveAmount><cbc:AllowanceTotalAmount currencyID="EUR">0.00</cbc:AllowanceTotalAmount><cbc:ChargeTotalAmount currencyID="EUR">0.00</cbc:ChargeTotalAmount><cbc:PayableAmount currencyID="EUR">121.00</cbc:PayableAmount></cac:LegalMonetaryTotal><cac:InvoiceLine><cbc:ID>1</cbc:ID><cbc:InvoicedQuantity unitCode="C62">1</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount><cac:Item><cbc:Description>Professional Services</cbc:Description><cbc:Name>Consulting</cbc:Name><cac:ClassifiedTaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>21</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:ClassifiedTaxCategory></cac:Item><cac:Price><cbc:PriceAmount currencyID="EUR">100.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine></Invoice>'
            Invoke-SqlUpdate -Query "INSERT INTO invoices (peppol_xml, status) VALUES ('$sampleXml', 'new')" -ConnectionName $connectionName -ErrorAction Stop
            Write-Host "Inserted sample invoice data."
        }
        
        Write-Host "Successfully connected to database '$dbDatabase' and verified schema." -ForegroundColor Green
    } catch {
        throw "Database connection failed: $($_.Exception.Message)"
    }
}

if ($MyInvocation.InvocationName -ne '.') {
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

Write-Host "Database connected. Starting polling loop (Interval: ${pollingIntervalSeconds}s)..." -ForegroundColor Cyan

while ($true) {
    try {
        # Check count first to avoid "No resultset" warning from SimplySql on empty SELECT
        $countCheck = Invoke-SqlQuery -Query "SELECT COUNT(*) AS c FROM invoices WHERE status = 'new';" -ConnectionName $connectionName -ErrorAction Stop
        
        if ($countCheck.c -gt 0) {
            $newInvoices = Invoke-SqlQuery -Query "SELECT id, peppol_xml FROM invoices WHERE status = 'new';" -ConnectionName $connectionName -ErrorAction Stop
        } else {
            $newInvoices = @()
        }
    }
    catch {
        Write-Host "Error querying database: $($_.Exception.Message). Attempting reconnection..." -ForegroundColor Yellow
        try { Connect-Database } catch { Write-Host "Reconnection failed: $($_.Exception.Message)" }
        Start-Sleep -Seconds $pollingIntervalSeconds
        continue
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
            if (-not (Test-InvoiceBusinessRules -xmlDoc $xmlDoc)) {
                throw "Validation failed: Business rules check (names, formats) failed."
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
            
            Convert-HtmlToPdf -htmlContent $htmlContent -outputPath $pdfPath -baseUri $outputDir

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
    
    if (-not $newInvoices) {
        Write-Host "No new invoices found. Sleeping for $pollingIntervalSeconds seconds."
        Start-Sleep -Seconds $pollingIntervalSeconds
    }
}
}
