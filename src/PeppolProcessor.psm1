<#
.SYNOPSIS
  Core logic for Peppol Invoice Processing.
#>

function Initialize-PeppolPdfLibrary {
    param([string]$LibPath)
    
    try {
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
        foreach ($dll in $dlls) { 
            $path = Join-Path $LibPath $dll
            if (Test-Path $path) {
                Add-Type -Path $path -ErrorAction SilentlyContinue 
            }
        }
        [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
        Write-Host "iText libraries loaded from $LibPath" -ForegroundColor Green
    } catch {
        Write-Host "FATAL: Could not load iText dependencies. Error: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Connect-Database {
    param(
        [string]$Server,
        [string]$User,
        [string]$Password,
        [string]$Database,
        [string]$ConnectionName
    )

    try {
        # Close existing connection if any
        try { Close-SqlConnection -ConnectionName $ConnectionName -ErrorAction Stop } catch {}

        $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($User, $secPass)
        
        # Connect without specifying a database first
        Open-MySqlConnection -Server $Server -Credential $cred -ConnectionName $ConnectionName -ErrorAction Stop
        
        # Ensure Database and Schema exist
        Invoke-SqlUpdate -Query "CREATE DATABASE IF NOT EXISTS $Database;" -ConnectionName $ConnectionName -ErrorAction Stop
        Invoke-SqlUpdate -Query "USE $Database;" -ConnectionName $ConnectionName -ErrorAction Stop
        
        $tableQuery = @"
CREATE TABLE IF NOT EXISTS invoices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    peppol_xml LONGTEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'new',
    processed_at DATETIME NULL,
    error_message TEXT NULL
);
"@
        Invoke-SqlUpdate -Query $tableQuery -ConnectionName $ConnectionName -ErrorAction Stop

        # Create Audit Table
        $auditTableQuery = @"
CREATE TABLE IF NOT EXISTS invoice_audit (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    invoice_id INT,
    action VARCHAR(50),
    log_time DATETIME DEFAULT CURRENT_TIMESTAMP
);
"@
        Invoke-SqlUpdate -Query $auditTableQuery -ConnectionName $ConnectionName -ErrorAction Stop

        # Create Trigger
        Invoke-SqlUpdate -Query "DROP TRIGGER IF EXISTS after_invoice_insert;" -ConnectionName $ConnectionName -ErrorAction Stop
        $triggerQuery = @"
CREATE TRIGGER after_invoice_insert 
AFTER INSERT ON invoices
FOR EACH ROW 
INSERT INTO invoice_audit (invoice_id, action) VALUES (NEW.id, 'NEW_INVOICE_RECEIVED');
"@
        Invoke-SqlUpdate -Query $triggerQuery -ConnectionName $ConnectionName -ErrorAction Stop
        
        Write-Host "Successfully connected to database '$Database' and verified schema." -ForegroundColor Green
    } catch {
        throw "Database connection failed: $($_.Exception.Message)"
    }
}

function Update-InvoiceStatus {
    param($InvoiceId, $Status, $ErrorMessage = $null, $ConnectionName)
    
    Write-Host "Updating invoice ID $InvoiceId to status '$Status'."
    $query = "UPDATE invoices SET status = '$Status', processed_at = NOW()"
    if ($ErrorMessage) {
        $sanitizedError = $ErrorMessage.Replace("'", "''")
        $query += ", error_message = '$sanitizedError'"
    }
    $query += " WHERE id = $InvoiceId;"
    
    Invoke-SqlUpdate -Query $query -ConnectionName $ConnectionName -ErrorAction Stop
}

function ConvertTo-InvoiceHtml {
    param([string]$XmlContent, [string]$XsltPath)
    
    $xslt = New-Object System.Xml.Xsl.XslCompiledTransform;
    $xslt.Load($XsltPath)
    $xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($XmlContent))
    $stringWriter = New-Object System.IO.StringWriter
    $xslt.Transform($xmlReader, $null, $stringWriter)
    return $stringWriter.ToString()
}

function Convert-HtmlToPdf {
    param([string]$HtmlContent, [string]$OutputPath, [string]$BaseUri)
    
    $pdfWriter = [iText.Kernel.Pdf.PdfWriter]::new($OutputPath)
    $pdfDocument = [iText.Kernel.Pdf.PdfDocument]::new($pdfWriter)
    $pdfDocument.SetDefaultPageSize([iText.Kernel.Geom.PageSize]::A4)
    $converterProperties = [iText.Html2pdf.ConverterProperties]::new()
    $converterProperties.SetBaseUri($BaseUri)
    [iText.Html2Pdf.HtmlConverter]::ConvertToPdf($HtmlContent, $pdfDocument, $converterProperties)
    $pdfDocument.Close()
}

function Test-InvoiceTotals {
    param([xml]$XmlDoc)
    if (-not $XmlDoc) { return $false }
    $ns = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
    $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
    $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')
    
    $declaredTotalNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:LineExtensionAmount", $ns)
    if (-not $declaredTotalNode) { return $false }
    $declaredTotal = [decimal]$declaredTotalNode.'#text'
    
    $lineItems = $XmlDoc.SelectNodes("//cac:InvoiceLine", $ns)
    $calculatedTotal = 0.0
    foreach ($item in $lineItems) {
        $lineAmount = [decimal]$item.SelectSingleNode("cbc:LineExtensionAmount", $ns).'#text'
        $quantity   = [decimal]$item.SelectSingleNode("cbc:InvoicedQuantity", $ns).'#text'
        $price      = [decimal]$item.SelectSingleNode("cac:Price/cbc:PriceAmount", $ns).'#text'
        
        if ([math]::Round($quantity * $price, 2) -ne $lineAmount) {
            return $false
        }
        $calculatedTotal += $lineAmount
    }
    
    # Check: LineExtension - Allowance + Charge = TaxExclusive
    $taxExclusiveNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:TaxExclusiveAmount", $ns)
    $allowanceNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:AllowanceTotalAmount", $ns)
    $chargeNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:ChargeTotalAmount", $ns)

    if ($taxExclusiveNode) {
        $taxExclusive = [decimal]$taxExclusiveNode.'#text'
        $allowance = if ($allowanceNode) { [decimal]$allowanceNode.'#text' } else { 0 }
        $charge = if ($chargeNode) { [decimal]$chargeNode.'#text' } else { 0 }
        
        $expectedExclusive = $declaredTotal - $allowance + $charge
        
        if ($taxExclusive -ne $expectedExclusive) {
             return $false
        }
    }

    return $declaredTotal -eq $calculatedTotal
}

function Test-InvoiceBusinessRules {
    param([xml]$XmlDoc)
    if (-not $XmlDoc) { return $false }
    $ns = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
    $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
    $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')
    
    $supplierName = $XmlDoc.SelectSingleNode("//cac:AccountingSupplierParty/cac:Party/cac:PartyName/cbc:Name", $ns)
    if (-not $supplierName -or [string]::IsNullOrWhiteSpace($supplierName.'#text')) { return $false }
    if ($supplierName.'#text' -match '^\d+$') {
        return $false
    }

    $customerName = $XmlDoc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party/cac:PartyName/cbc:Name", $ns)
    if (-not $customerName -or [string]::IsNullOrWhiteSpace($customerName.'#text')) {
        return $false
    }
    if ($customerName.'#text' -match '^\d+$') {
        return $false
    }
    
    $issueDate = $XmlDoc.SelectSingleNode("//cbc:IssueDate", $ns)
    if (-not $issueDate -or [string]::IsNullOrWhiteSpace($issueDate.'#text')) { return $false }
    
    # Validate Currency Consistency
    $docCurrencyNode = $XmlDoc.SelectSingleNode("//cbc:DocumentCurrencyCode", $ns)
    if ($docCurrencyNode) {
        $docCurrency = $docCurrencyNode.'#text'
        $lineAmounts = $XmlDoc.SelectNodes("//cac:InvoiceLine/cbc:LineExtensionAmount", $ns)
        foreach ($amt in $lineAmounts) {
            if ($amt.HasAttribute("currencyID") -and $amt.GetAttribute("currencyID") -ne $docCurrency) {
                 return $false
            }
        }
    }

    # Validate Non-Negative Values (Price and Quantity)
    $lineItems = $XmlDoc.SelectNodes("//cac:InvoiceLine", $ns)
    foreach ($item in $lineItems) {
        $quantityNode = $item.SelectSingleNode("cbc:InvoicedQuantity", $ns)
        if ($quantityNode) {
            $quantity = [decimal]$quantityNode.'#text'
            if ($quantity -lt 0) {
                return $false
            }
        }

        $priceNode = $item.SelectSingleNode("cac:Price/cbc:PriceAmount", $ns)
        if ($priceNode) {
            $price = [decimal]$priceNode.'#text'
            if ($price -lt 0) {
                return $false
            }
        }
    }

    return $true
}

function Test-InvoiceVat {
    param([xml]$XmlDoc)
    if (-not $XmlDoc) { return $false }

    $ns = New-Object System.Xml.XmlNamespaceManager($XmlDoc.NameTable)
    $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
    $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')

    $subtotals = $XmlDoc.SelectNodes("//cac:TaxTotal/cac:TaxSubtotal", $ns)
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
            return $false
        }
    }

    # Check: Compare Sum of TaxableAmounts with LegalMonetaryTotal/TaxExclusiveAmount
    $taxExclusiveNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:TaxExclusiveAmount", $ns)
    if ($taxExclusiveNode) {
        $declaredTaxExclusive = [decimal]$taxExclusiveNode.'#text'
        if ($declaredTaxExclusive -ne $totalTaxableBase) {
            return $false
        }

        # Check: TaxExclusive + Tax = TaxInclusive
        $taxInclusiveNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:TaxInclusiveAmount", $ns)
        if ($taxInclusiveNode) {
            $declaredTaxInclusive = [decimal]$taxInclusiveNode.'#text'
            $calculatedInclusive = $declaredTaxExclusive + $totalTaxAmount
            if ($declaredTaxInclusive -ne $calculatedInclusive) {
                return $false
            }
            
            # Check: TaxInclusive = Payable (assuming no prepaid/charges for this scope)
            $payableNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:PayableAmount", $ns)
            if ($payableNode -and ([decimal]$payableNode.'#text' -ne $declaredTaxInclusive)) {
                return $false
            }
        }
    }

    return $true
}

function Test-AuthToken {
    param([string]$Token)
    $validToken = $env:API_TOKEN
    if ([string]::IsNullOrEmpty($validToken)) { return $false }
    return $Token -eq $validToken
}

function Publish-ToCloud {
    param([string]$PdfPath)
    
    # Simulate uploading to a cloud folder (e.g., OneDrive/SharePoint sync folder)
    $parentDir = Split-Path $PdfPath
    $cloudDir = Join-Path $parentDir "cloud_sync"
    
    if (-not (Test-Path $cloudDir)) { New-Item -ItemType Directory -Path $cloudDir -Force | Out-Null }
    
    Copy-Item -Path $PdfPath -Destination $cloudDir -Force
    Write-Host "   -> Uploaded to Cloud Storage (Simulated at $cloudDir)" -ForegroundColor Cyan
}

function Start-PeppolProcessor {
    param(
        [string]$DbHost = $env:DB_HOST,
        [string]$DbUser = $env:DB_USER,
        [string]$DbPassword = $env:DB_PASSWORD,
        [string]$DbDatabase = $env:DB_DATABASE,
        [string]$ConnectionName = "InvoicesDB",
        [string]$LibPath = "/app/lib",
        [string]$XsltPath = "/app/templates/invoice-transform.xslt",
        [string]$OutputDir = "/app/output",
        [int]$PollingIntervalSeconds = 5
    )

    # Initialize Libraries
    Initialize-PeppolPdfLibrary -LibPath $LibPath

    Write-Host "Invoice processing started. Waiting for database to be ready..."
    Start-Sleep -Seconds 15 # Give the database time to initialize

    try {
        if (-not (Get-Module -Name SimplySql -ErrorAction SilentlyContinue)) {
            Import-Module SimplySql -ErrorAction Stop
        }
        Connect-Database -Server $DbHost -User $DbUser -Password $DbPassword -Database $DbDatabase -ConnectionName $ConnectionName
    }
    catch {
        Write-Host "FATAL: Could not connect to the database. Error: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "Database connected. Starting polling loop (Interval: ${PollingIntervalSeconds}s)..." -ForegroundColor Cyan

    while ($true) {
        try {
            # Check count first to avoid "No resultset" warning from SimplySql on empty SELECT
            $countCheck = Invoke-SqlQuery -Query "SELECT COUNT(*) AS c FROM invoices WHERE status = 'new';" -ConnectionName $ConnectionName -ErrorAction Stop
            
            if ($countCheck.c -gt 0) {
                $newInvoices = Invoke-SqlQuery -Query "SELECT id, peppol_xml FROM invoices WHERE status = 'new';" -ConnectionName $ConnectionName -ErrorAction Stop
            } else {
                $newInvoices = @()
            }
        }
        catch {
            Write-Host "Error querying database: $($_.Exception.Message). Attempting reconnection..." -ForegroundColor Yellow
            try { Connect-Database -Server $DbHost -User $DbUser -Password $DbPassword -Database $DbDatabase -ConnectionName $ConnectionName } catch { Write-Host "Reconnection failed: $($_.Exception.Message)" }
            Start-Sleep -Seconds $PollingIntervalSeconds
            continue
        }
        
        foreach ($invoice in $newInvoices) {
            $invoiceId = $invoice.id
            Write-Host "Processing invoice ID: $invoiceId"
            
            try {
                # 1. Validate
                $xmlDoc = [xml]$invoice.peppol_xml
                if (-not (Test-InvoiceTotals -XmlDoc $xmlDoc)) { throw "Validation failed: Totals mismatch." }
                if (-not (Test-InvoiceBusinessRules -XmlDoc $xmlDoc)) { throw "Validation failed: Business rules check failed." }
                if (-not (Test-InvoiceVat -XmlDoc $xmlDoc)) { throw "Validation failed: VAT calculation incorrect." }

                # 2. Status processing
                Update-InvoiceStatus -InvoiceId $invoiceId -Status 'processing' -ConnectionName $ConnectionName

                # 3. Transform
                $htmlContent = ConvertTo-InvoiceHtml -XmlContent $invoice.peppol_xml -XsltPath $XsltPath
                if (-not $htmlContent) { throw "Transformation to HTML failed." }

                # 4. PDF
                $pdfPath = Join-Path -Path $OutputDir -ChildPath "invoice-$($invoiceId)-$(Get-Date -Format 'yyyyMMddHHmmss').pdf"
                Convert-HtmlToPdf -HtmlContent $htmlContent -OutputPath $pdfPath -BaseUri $OutputDir
                Write-Host "Successfully generated PDF: $pdfPath"

                # Cloud
                Publish-ToCloud -PdfPath $pdfPath

                # 5. Status processed
                Update-InvoiceStatus -InvoiceId $invoiceId -Status 'processed' -ConnectionName $ConnectionName
            }
            catch {
                $errorMessage = "Failed to process invoice ID $invoiceId. Error: $($_.Exception.Message)"
                Write-Host $errorMessage -ForegroundColor Red
                Update-InvoiceStatus -InvoiceId $invoiceId -Status 'error' -ErrorMessage $errorMessage -ConnectionName $ConnectionName
            }
        }
        
        if (-not $newInvoices) {
            Write-Host "No new invoices found. Sleeping for $PollingIntervalSeconds seconds."
            Start-Sleep -Seconds $PollingIntervalSeconds
        }
    }
}

function Import-PeppolData {
    param(
        [string]$SourcePath,
        [string]$DbHost = "127.0.0.1",
        [string]$DbUser = "root",
        [string]$DbPassword = "",
        [string]$DbDatabase = "invoices_db"
    )

    $connectionName = "InvoicesDB_Insert"

    try {
        if (-not (Get-Module -Name SimplySql -ErrorAction SilentlyContinue)) { Import-Module SimplySql -ErrorAction Stop }
        
        Write-Host "Connecting to database..."
        $secPass = ConvertTo-SecureString $DbPassword -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($DbUser, $secPass)
        Open-MySqlConnection -Server $DbHost -Credential $cred -ConnectionName $connectionName -Database $DbDatabase -ErrorAction Stop

        if (Test-Path $SourcePath -PathType Leaf) {
            $files = @(Get-Item $SourcePath)
        } else {
            $files = Get-ChildItem -Path $SourcePath -Filter "*.xml"
        }
        
        foreach ($file in $files) {
            Write-Host "Inserting $($file.Name)..." -NoNewline
            $xmlContent = Get-Content $file.FullName -Raw
            $safeXml = $xmlContent.Replace("'", "''")
            $query = "INSERT INTO invoices (peppol_xml, status) VALUES ('$safeXml', 'new');"
            Invoke-SqlUpdate -Query $query -ConnectionName $connectionName -ErrorAction Stop
            Write-Host " Done." -ForegroundColor Green
        }
    } catch {
        Write-Error "An error occurred: $($_.Exception.Message)"
    } finally {
        try { Close-SqlConnection -ConnectionName $connectionName } catch {}
    }
}

function New-PeppolReport {
    param(
        [string]$DbHost = $env:DB_HOST,
        [string]$DbUser = $env:DB_USER,
        [string]$DbPassword = $env:DB_PASSWORD,
        [string]$DbDatabase = $env:DB_DATABASE,
        [string]$ReportPath = "/app/output/status_report.html"
    )

    $connectionName = "InvoicesDB_Report"

    try {
        if (-not (Get-Module -Name SimplySql -ErrorAction SilentlyContinue)) { Import-Module SimplySql -ErrorAction Stop }
        
        $secPass = ConvertTo-SecureString $DbPassword -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($DbUser, $secPass)
        Open-MySqlConnection -Server $DbHost -Credential $cred -ConnectionName $connectionName -Database $DbDatabase -ErrorAction Stop

        # Get Statistics
        $stats = Invoke-SqlQuery -Query "SELECT status, COUNT(*) as count FROM invoices GROUP BY status" -ConnectionName $connectionName
        
        # Get Recent Errors
        $errors = Invoke-SqlQuery -Query "SELECT id, processed_at, error_message FROM invoices WHERE status = 'error' ORDER BY id DESC LIMIT 10" -ConnectionName $connectionName

        # Build HTML
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Peppol Processing Report</title>
    <style>
        body { font-family: sans-serif; padding: 20px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .status-new { color: blue; }
        .status-processed { color: green; }
        .status-error { color: red; }
    </style>
</head>
<body>
    <h1>System Status Report</h1>
    <p>Generated at: $(Get-Date)</p>

    <h2>Overview</h2>
    <table>
        <tr><th>Status</th><th>Count</th></tr>
        $($stats | ForEach-Object { "<tr><td>$($_.status)</td><td>$($_.count)</td></tr>" })
    </table>

    <h2>Recent Errors</h2>
    <table>
        <tr><th>ID</th><th>Time</th><th>Error Message</th></tr>
        $($errors | ForEach-Object { "<tr><td>$($_.id)</td><td>$($_.processed_at)</td><td class='status-error'>$($_.error_message)</td></tr>" })
    </table>
</body>
</html>
"@

        $html | Out-File -FilePath $ReportPath -Encoding UTF8
        Write-Host "Report generated at: $ReportPath" -ForegroundColor Green

    } catch {
        Write-Error "Failed to generate report: $($_.Exception.Message)"
    } finally {
        try { Close-SqlConnection -ConnectionName $connectionName } catch {}
    }
}

Export-ModuleMember -Function *