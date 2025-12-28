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
# --- Main Processing Loop ---

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
# Import Custom Module
Import-Module "$PSScriptRoot/PeppolProcessor.psd1" -Force

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
    
    if (-not $xmlDoc) {
        Write-Host "Validation Error: XML content is empty or invalid."
        return $false
    }

    # Define namespaces for XPath
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
    $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')
    
    # Get the declared total from LegalMonetaryTotal
    $declaredTotalNode = $xmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:LineExtensionAmount", $ns)
    if (-not $declaredTotalNode) { return $false } # No total found, invalid
    $declaredTotal = [decimal]$declaredTotalNode.'#text'
    
    # Calculate the sum of all invoice lines
    $lineItems = $xmlDoc.SelectNodes("//cac:InvoiceLine", $ns)
    $calculatedTotal = 0.0

    foreach ($item in $lineItems) {
        $lineAmount = [decimal]$item.SelectSingleNode("cbc:LineExtensionAmount", $ns).'#text'
        $quantity   = [decimal]$item.SelectSingleNode("cbc:InvoicedQuantity", $ns).'#text'
        $price      = [decimal]$item.SelectSingleNode("cac:Price/cbc:PriceAmount", $ns).'#text'
        
        if ([math]::Round($quantity * $price, 2) -ne $lineAmount) {
            Write-Host "Validation Error: Line math incorrect. $quantity * $price != $lineAmount"
            return $false
        }
        $calculatedTotal += $lineAmount
    }
    
    Write-Host "Validation: Declared Total = $declaredTotal, Calculated Total = $calculatedTotal"
    
    # Check: LineExtension - Allowance + Charge = TaxExclusive
    $taxExclusiveNode = $xmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:TaxExclusiveAmount", $ns)
    $allowanceNode = $xmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:AllowanceTotalAmount", $ns)
    $chargeNode = $xmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:ChargeTotalAmount", $ns)

    if ($taxExclusiveNode) {
        $taxExclusive = [decimal]$taxExclusiveNode.'#text'
        $allowance = if ($allowanceNode) { [decimal]$allowanceNode.'#text' } else { 0 }
        $charge = if ($chargeNode) { [decimal]$chargeNode.'#text' } else { 0 }
        
        $expectedExclusive = $declaredTotal - $allowance + $charge
        
        if ($taxExclusive -ne $expectedExclusive) {
             Write-Host "Validation Error: Tax Exclusive Amount mismatch. LineExtension ($declaredTotal) - Allowance ($allowance) + Charge ($charge) != TaxExclusive ($taxExclusive)"
             return $false
        }
    }

    # Compare the totals
    return $declaredTotal -eq $calculatedTotal
}

function Test-InvoiceBusinessRules {
    param(
        [xml]$xmlDoc
    )
    
    if (-not $xmlDoc) {
        Write-Host "Validation Error: XML content is empty or invalid."
        return $false
    }

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

    # Validate Issue Date
    $issueDate = $xmlDoc.SelectSingleNode("//cbc:IssueDate", $ns)
    if (-not $issueDate -or [string]::IsNullOrWhiteSpace($issueDate.'#text')) {
        Write-Host "Validation Error: Issue Date is missing."
        return $false
    }

    # Validate Currency Consistency
    $docCurrencyNode = $xmlDoc.SelectSingleNode("//cbc:DocumentCurrencyCode", $ns)
    if ($docCurrencyNode) {
        $docCurrency = $docCurrencyNode.'#text'
        $lineAmounts = $xmlDoc.SelectNodes("//cac:InvoiceLine/cbc:LineExtensionAmount", $ns)
        foreach ($amt in $lineAmounts) {
            if ($amt.HasAttribute("currencyID") -and $amt.GetAttribute("currencyID") -ne $docCurrency) {
                 Write-Host "Validation Error: Currency mismatch. Document: $docCurrency, Line: $($amt.GetAttribute('currencyID'))"
                 return $false
            }
        }
    }

    return $true
}

function Test-InvoiceVat {
    param(
        [xml]$xmlDoc
    )
    
    if (-not $xmlDoc) { return $false }

    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
    $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')

    $subtotals = $xmlDoc.SelectNodes("//cac:TaxTotal/cac:TaxSubtotal", $ns)
    $totalTaxableBase = 0.0
    $totalTaxAmount = 0.0

    foreach ($subtotal in $subtotals) {
        $taxable = [decimal]$subtotal.SelectSingleNode("cbc:TaxableAmount", $ns).'#text'
        $taxAmount = [decimal]$subtotal.SelectSingleNode("cbc:TaxAmount", $ns).'#text'
        $percent = [decimal]$subtotal.SelectSingleNode("cac:TaxCategory/cbc:Percent", $ns).'#text'
        $totalTaxableBase += $taxable
        $totalTaxAmount += $taxAmount

        $calculatedTax = [math]::Round($taxable * ($percent / 100), 2)

        if ($calculatedTax -ne $taxAmount) {
            Write-Host "Validation Error: VAT mismatch. Taxable: $taxable, Percent: $percent, Declared: $taxAmount, Calculated: $calculatedTax"
            return $false
        }
    }

    # Check: Compare Sum of TaxableAmounts with LegalMonetaryTotal/TaxExclusiveAmount
    $taxExclusiveNode = $xmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:TaxExclusiveAmount", $ns)
    if ($taxExclusiveNode) {
        $declaredTaxExclusive = [decimal]$taxExclusiveNode.'#text'
        if ($declaredTaxExclusive -ne $totalTaxableBase) {
            Write-Host "Validation Error: Taxable Base Mismatch. LegalMonetaryTotal/TaxExclusiveAmount ($declaredTaxExclusive) does not match sum of TaxSubtotal/TaxableAmount ($totalTaxableBase)."
            return $false
        }

        # Check: TaxExclusive + Tax = TaxInclusive
        $taxInclusiveNode = $xmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:TaxInclusiveAmount", $ns)
        if ($taxInclusiveNode) {
            $declaredTaxInclusive = [decimal]$taxInclusiveNode.'#text'
            $calculatedInclusive = $declaredTaxExclusive + $totalTaxAmount
            if ($declaredTaxInclusive -ne $calculatedInclusive) {
                Write-Host "Validation Error: Total Mismatch. Exclusive ($declaredTaxExclusive) + Tax ($totalTaxAmount) != Inclusive ($declaredTaxInclusive)"
                return $false
            }
            
            # Check: TaxInclusive = Payable (assuming no prepaid/charges for this scope)
            $payableNode = $xmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:PayableAmount", $ns)
            if ($payableNode -and ([decimal]$payableNode.'#text' -ne $declaredTaxInclusive)) {
                Write-Host "Validation Error: Payable Amount mismatch."
                return $false
            }
        }
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

function Test-AuthToken {
    param(
        [string]$token
    )
    
    # Simulate checking a Bearer token against a secure environment variable
    $validToken = $env:API_TOKEN
    
    if ([string]::IsNullOrEmpty($validToken)) {
        Write-Host "Security Warning: API_TOKEN environment variable is not set."
        return $false
    }
    
    return $token -eq $validToken
}

# --- Main Processing Loop ---

# Load iText Dependencies
# Initialize Libraries
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
    Initialize-PeppolPdfLibrary -LibPath "/app/lib"
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
    Connect-Database -Server $dbHost -User $dbUser -Password $dbPassword -Database $dbDatabase -ConnectionName $connectionName
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
        try { Connect-Database -Server $dbHost -User $dbUser -Password $dbPassword -Database $dbDatabase -ConnectionName $connectionName } catch { Write-Host "Reconnection failed: $($_.Exception.Message)" }
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
            if (-not (Test-InvoiceVat -xmlDoc $xmlDoc)) {
                throw "Validation failed: VAT calculation is incorrect."
            }

            # 2. Set status to 'processing'
            Update-InvoiceStatus -InvoiceId $invoiceId -Status 'processing' -ConnectionName $connectionName

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
            Update-InvoiceStatus -InvoiceId $invoiceId -Status 'processed' -ConnectionName $connectionName
        }
        catch {
            $errorMessage = "Failed to process invoice ID $invoiceId. Error: $($_.Exception.Message)"
            Write-Host $errorMessage -ForegroundColor Red
            Update-InvoiceStatus -InvoiceId $invoiceId -Status 'error' -ErrorMessage $errorMessage -ConnectionName $connectionName
        }
    }
    
    if (-not $newInvoices) {
        Write-Host "No new invoices found. Sleeping for $pollingIntervalSeconds seconds."
        Start-Sleep -Seconds $pollingIntervalSeconds
    }
}
}
