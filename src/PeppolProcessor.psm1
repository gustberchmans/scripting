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
            Write-Host "Validation Error: Line math incorrect. $quantity * $price != $lineAmount"
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
             Write-Host "Validation Error: Tax Exclusive Amount mismatch. LineExtension ($declaredTotal) - Allowance ($allowance) + Charge ($charge) != TaxExclusive ($taxExclusive)"
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
        Write-Host "Validation Error: Supplier Name '$($supplierName.'#text')' cannot be purely numeric."
        return $false
    }

    $customerName = $XmlDoc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party/cac:PartyName/cbc:Name", $ns)
    if (-not $customerName -or [string]::IsNullOrWhiteSpace($customerName.'#text')) {
        Write-Host "Validation Error: Customer Name is missing or empty."
        return $false
    }
    if ($customerName.'#text' -match '^\d+$') {
        Write-Host "Validation Error: Customer Name '$($customerName.'#text')' cannot be purely numeric."
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
                 Write-Host "Validation Error: Currency mismatch. Document: $docCurrency, Line: $($amt.GetAttribute('currencyID'))"
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
                Write-Host "Validation Error: Item Quantity cannot be negative ($quantity)."
                return $false
            }
        }

        $priceNode = $item.SelectSingleNode("cac:Price/cbc:PriceAmount", $ns)
        if ($priceNode) {
            $price = [decimal]$priceNode.'#text'
            if ($price -lt 0) {
                Write-Host "Validation Error: Item Price cannot be negative ($price)."
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
            Write-Host "Validation Error: VAT mismatch. Taxable: $taxable, Percent: $percent, Declared: $taxAmount, Calculated: $calculatedTax"
            return $false
        }
    }

    # Check: Compare Sum of TaxableAmounts with LegalMonetaryTotal/TaxExclusiveAmount
    $taxExclusiveNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:TaxExclusiveAmount", $ns)
    if ($taxExclusiveNode) {
        $declaredTaxExclusive = [decimal]$taxExclusiveNode.'#text'
        if ($declaredTaxExclusive -ne $totalTaxableBase) {
            Write-Host "Validation Error: Taxable Base Mismatch. LegalMonetaryTotal/TaxExclusiveAmount ($declaredTaxExclusive) does not match sum of TaxSubtotal/TaxableAmount ($totalTaxableBase)."
            return $false
        }

        # Check: TaxExclusive + Tax = TaxInclusive
        $taxInclusiveNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:TaxInclusiveAmount", $ns)
        if ($taxInclusiveNode) {
            $declaredTaxInclusive = [decimal]$taxInclusiveNode.'#text'
            $calculatedInclusive = $declaredTaxExclusive + $totalTaxAmount
            if ($declaredTaxInclusive -ne $calculatedInclusive) {
                Write-Host "Validation Error: Total Mismatch. Exclusive ($declaredTaxExclusive) + Tax ($totalTaxAmount) != Inclusive ($declaredTaxInclusive)"
                return $false
            }
            
            # Check: TaxInclusive = Payable (assuming no prepaid/charges for this scope)
            $payableNode = $XmlDoc.SelectSingleNode("//cac:LegalMonetaryTotal/cbc:PayableAmount", $ns)
            if ($payableNode -and ([decimal]$payableNode.'#text' -ne $declaredTaxInclusive)) {
                Write-Host "Validation Error: Payable Amount mismatch."
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

Export-ModuleMember -Function *