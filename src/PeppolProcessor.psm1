<#
.SYNOPSIS
  Core logic for Peppol Invoice Processing.
#>

<#
.SYNOPSIS
  Loads required iText 7 and BouncyCastle assemblies into the PowerShell session.
.DESCRIPTION
  This function loops through a list of essential DLL files in the specified library path
  and loads them using Add-Type. It also registers system encoding providers needed by iText.
.PARAMETER LibPath
  The directory path containing the .NET assemblies.
#>
function Initialize-PeppolPdfLibrary {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibPath
    )
    
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

<#
.SYNOPSIS
  Establishes a connection to the MySQL database, ensures the database schema is up-to-date,
  creates the necessary tables (invoices and audit logging), and registers the database triggers.
.DESCRIPTION
  This function uses the SimplySql module to open a MySQL connection. It initializes the database
  and ensures that columns for storing XML, processing status, and VAT numbers exist.
.PARAMETER Server
  The host name or IP address of the MySQL database server.
.PARAMETER User
  The username used to connect to the database.
.PARAMETER Password
  De password used to connect to the database.
.PARAMETER Database
  The name of the database to use or create.
.PARAMETER ConnectionName
  The symbolic name for the SimplySql connection.
.EXAMPLE
  Connect-Database -Server "localhost" -User "root" -Password "secret" -Database "invoices_db" -ConnectionName "InvoicesDB"
#>
function Connect-Database {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$User,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Database,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionName
    )

    try {
        # Close existing connection if any to release resources and avoid connection leak
        try { Close-SqlConnection -ConnectionName $ConnectionName -ErrorAction Stop } catch {}

        # Safely convert plain text password to SecureString for PSDecential
        $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($User, $secPass)
        
        # Connect without specifying a database first to ensure the server is reachable
        Open-MySqlConnection -Server $Server -Credential $cred -ConnectionName $ConnectionName -ErrorAction Stop
        
        # Ensure Database exists and switch context to it
        Invoke-SqlUpdate -Query "CREATE DATABASE IF NOT EXISTS $Database;" -ConnectionName $ConnectionName -ErrorAction Stop
        Invoke-SqlUpdate -Query "USE $Database;" -ConnectionName $ConnectionName -ErrorAction Stop
        
        # Schema definition for core invoices table (contains raw XML and extracted metadata)
        $tableQuery = @"
CREATE TABLE IF NOT EXISTS invoices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    peppol_xml LONGTEXT NOT NULL,
    supplier_vat VARCHAR(50) NULL,
    customer_vat VARCHAR(50) NULL,
    status VARCHAR(50) DEFAULT 'new',
    processed_at DATETIME NULL,
    error_message TEXT NULL
);
"@
        Invoke-SqlUpdate -Query $tableQuery -ConnectionName $ConnectionName -ErrorAction Stop

        # Schema migrations: check and add supplier_vat column if missing
        $checkColQuery1 = "SELECT count(*) as c FROM information_schema.columns WHERE table_schema = '$Database' AND table_name = 'invoices' AND column_name = 'supplier_vat';"
        $colExists1 = Invoke-SqlQuery -Query $checkColQuery1 -ConnectionName $ConnectionName -ErrorAction Stop
        if ($colExists1.c -eq 0) {
            Invoke-SqlUpdate -Query "ALTER TABLE invoices ADD COLUMN supplier_vat VARCHAR(50) NULL;" -ConnectionName $ConnectionName -ErrorAction Stop
        }

        # Schema migrations: check and add customer_vat column if missing
        $checkColQuery2 = "SELECT count(*) as c FROM information_schema.columns WHERE table_schema = '$Database' AND table_name = 'invoices' AND column_name = 'customer_vat';"
        $colExists2 = Invoke-SqlQuery -Query $checkColQuery2 -ConnectionName $ConnectionName -ErrorAction Stop
        if ($colExists2.c -eq 0) {
            Invoke-SqlUpdate -Query "ALTER TABLE invoices ADD COLUMN customer_vat VARCHAR(50) NULL;" -ConnectionName $ConnectionName -ErrorAction Stop
        }
        
        # Create Audit Table for tracing invoice status transitions
        $auditTableQuery = @"
CREATE TABLE IF NOT EXISTS invoice_audit (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    invoice_id INT,
    action VARCHAR(50),
    log_time DATETIME DEFAULT CURRENT_TIMESTAMP
);
"@
        Invoke-SqlUpdate -Query $auditTableQuery -ConnectionName $ConnectionName -ErrorAction Stop

        # Register MySQL Trigger to audit log new invoices automatically
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

<#
.SYNOPSIS
  Updates the processing status of an invoice in the database.
.DESCRIPTION
  This function updates the status of an invoice (e.g., to 'processing', 'processed', or 'error'),
  sets the processing timestamp, and saves any error messages or extracted supplier/customer VAT numbers.
.PARAMETER InvoiceId
  The ID of the invoice to update.
.PARAMETER Status
  The new status of the invoice. Must be one of 'new', 'processing', 'processed', or 'error'.
.PARAMETER ErrorMessage
  An optional error message to save if the processing failed.
.PARAMETER SupplierVat
  An optional supplier VAT number extracted from the XML to be saved in the database.
.PARAMETER CustomerVat
  An optional customer VAT number extracted from the XML to be saved in the database.
.PARAMETER ConnectionName
  The name of the database connection.
#>
function Update-InvoiceStatus {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$InvoiceId,

        [Parameter(Mandatory=$true)]
        [ValidateSet('new', 'processing', 'processed', 'error')]
        [string]$Status,

        [Parameter(Mandatory=$false)]
        [string]$ErrorMessage = $null,

        [Parameter(Mandatory=$false)]
        [string]$SupplierVat = $null,

        [Parameter(Mandatory=$false)]
        [string]$CustomerVat = $null,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionName = "InvoicesDB"
    )
    
    Write-Host "Updating invoice ID $InvoiceId to status '$Status'."
    $query = "UPDATE invoices SET status = '$Status', processed_at = NOW()"
    if ($ErrorMessage) {
        $sanitizedError = $ErrorMessage.Replace("'", "''")
        $query += ", error_message = '$sanitizedError'"
    }
    if ($SupplierVat) {
        $sanitizedSupplier = $SupplierVat.Replace("'", "''")
        $query += ", supplier_vat = '$sanitizedSupplier'"
    }
    if ($CustomerVat) {
        $sanitizedCustomer = $CustomerVat.Replace("'", "''")
        $query += ", customer_vat = '$sanitizedCustomer'"
    }
    $query += " WHERE id = $InvoiceId;"
    
    Invoke-SqlUpdate -Query $query -ConnectionName $ConnectionName -ErrorAction Stop
}

<#
.SYNOPSIS
  Transforms raw UBL XML content into HTML using an XSLT template.
.DESCRIPTION
  This function uses .NET's System.Xml.Xsl.XslCompiledTransform class to parse and transform
  an XML string input into an HTML string output based on a stylesheet path.
.PARAMETER XmlContent
  The raw Peppol UBL XML string to transform.
.PARAMETER XsltPath
  The filesystem path to the XSLT stylesheet file.
.RETURN
  A string containing the generated HTML document.
#>
function ConvertTo-InvoiceHtml {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$XmlContent,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$XsltPath
    )
    
    $xslt = New-Object System.Xml.Xsl.XslCompiledTransform;
    $xslt.Load($XsltPath)
    $xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($XmlContent))
    $stringWriter = New-Object System.IO.StringWriter
    $xslt.Transform($xmlReader, $null, $stringWriter)
    return $stringWriter.ToString()
}

<#
.SYNOPSIS
  Converts an HTML string into a PDF file using iText 7 html2pdf.
.DESCRIPTION
  This function uses the imported iText 7 html2pdf library's HtmlConverter class to render
  the HTML document to an A4 PDF document.
.PARAMETER HtmlContent
  The HTML document string to render.
.PARAMETER OutputPath
  The destination filepath for the generated PDF.
.PARAMETER BaseUri
  The base directory path used by the HTML renderer to resolve relative paths (e.g. stylesheet assets).
#>
function Convert-HtmlToPdf {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$HtmlContent,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUri
    )
    
    $pdfWriter = [iText.Kernel.Pdf.PdfWriter]::new($OutputPath)
    $pdfDocument = [iText.Kernel.Pdf.PdfDocument]::new($pdfWriter)
    $pdfDocument.SetDefaultPageSize([iText.Kernel.Geom.PageSize]::A4)
    $converterProperties = [iText.Html2pdf.ConverterProperties]::new()
    $converterProperties.SetBaseUri($BaseUri)
    [iText.Html2Pdf.HtmlConverter]::ConvertToPdf($HtmlContent, $pdfDocument, $converterProperties)
    $pdfDocument.Close()
}

<#
.SYNOPSIS
  Validates that line item totals sum up to the invoice header totals.
.DESCRIPTION
  This function parses the XML document to verify that the sum of all individual InvoiceLine/LineExtensionAmount values
  matches the header LegalMonetaryTotal/LineExtensionAmount, and that line extensions correctly balance with allowances and charges.
.PARAMETER XmlDoc
  The parsed [xml] document of the Peppol invoice.
.RETURN
  True if the totals match and are consistent, False otherwise.
#>
function Test-InvoiceTotals {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [xml]$XmlDoc
    )
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

<#
.SYNOPSIS
  Validates a VAT (BTW) number format.
.DESCRIPTION
  This helper function cleans the VAT number by removing common separator characters 
  (spaces, periods, hyphens) and checks it against NL, BE, and general EU format regular expressions.
.PARAMETER VatNumber
  The VAT identifier string to validate.
.OUTPUTS
  [bool] True if the VAT format is valid, False otherwise.
.EXAMPLE
  Test-VatNumberFormat -VatNumber "NL123456789B01"
#>
function Test-VatNumberFormat {
    param(
        [Parameter(Mandatory=$false)]
        [string]$VatNumber
    )
    
    if ([string]::IsNullOrWhiteSpace($VatNumber)) {
        return $false
    }
    
    # Strip separators and force uppercase
    $cleaned = $VatNumber.Replace(" ", "").Replace(".", "").Replace("-", "").ToUpper()
    
    # NL format: NL + 9 digits + B + 2 digits (e.g. NL123456789B01)
    if ($cleaned -match '^NL\d{9}B\d{2}$') {
        return $true
    }
    
    # BE format: BE + 10 digits (e.g. BE0123456789)
    if ($cleaned -match '^BE\d{10}$') {
        return $true
    }
    
    # General EU VAT format: 2-letter country code + 2 to 12 alphanumeric characters
    if ($cleaned -match '^[A-Z]{2}[A-Z0-9]{2,12}$') {
        return $true
    }
    
    return $false
}

<#
.SYNOPSIS
  Validates standard VAT identification number formats for EU member states.
.DESCRIPTION
  This function cleans the input VAT number (removes non-alphanumeric characters) and checks it
  against specific regular expressions for the Netherlands (NL), Belgium (BE), Germany (DE),
  France (FR), and a generic EU fallback pattern.
.PARAMETER VatNumber
  The VAT string to validate.
.RETURN
  True if the format is correct, False otherwise.
#>
function Test-VatNumberFormat {
    param(
        [Parameter(Mandatory=$false)]
        [string]$VatNumber = $null
    )

    if ([string]::IsNullOrWhiteSpace($VatNumber)) { return $false }

    # Clean the input by removing spaces, dots, dashes, etc., and uppercase it
    $clean = ($VatNumber -replace '[^A-Za-z0-9]', '').ToUpper()

    # General structure check: must start with 2 letters followed by 2 to 12 alphanumeric characters
    if ($clean -notmatch '^[A-Z]{2}[A-Z0-9]{2,12}$') { return $false }

    $country = $clean.Substring(0, 2)
    $rest = $clean.Substring(2)

    # VAT numbers cannot be purely alphabetic after the country code
    if ($rest -match '^[A-Z]+$') { return $false }

    # Check country-specific formats
    switch ($country) {
        "NL" { return $rest -match '^\d{9}B\d{2}$' }
        "BE" { return $rest -match '^\d{9,10}$' }
        "DE" { return $rest -match '^\d{9}$' }
        "FR" { return $rest -match '^[A-Z0-9]{2}\d{9}$' }
        default {
            # General fallback check: must contain at least one digit
            return $rest -match '\d'
        }
    }
}

<#
.SYNOPSIS
  Validates standard UBL business rules on the XML invoice document.
.DESCRIPTION
  This function checks essential billing rules: supplier and customer names must exist and not be purely numeric,
  the issue date must be present, document currency must match line currency codes, quantities/prices must be non-negative,
  and supplier and customer VAT numbers must be present and valid.
.PARAMETER XmlDoc
  The parsed [xml] document of the Peppol invoice.
.RETURN
  True if all business rules check out, False otherwise.
#>
function Test-InvoiceBusinessRules {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [xml]$XmlDoc
    )
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

    # Validate VAT Numbers (Supplier and Customer)
    # Extract Supplier VAT (BT-31)
    $supplierVatNode = $XmlDoc.SelectSingleNode("//cac:AccountingSupplierParty/cac:Party/cac:PartyTaxScheme[cac:TaxScheme/cbc:ID='VAT']/cbc:CompanyID", $ns)
    if (-not $supplierVatNode) {
        $supplierVatNode = $XmlDoc.SelectSingleNode("//cac:AccountingSupplierParty/cac:Party/cac:PartyTaxScheme/cbc:CompanyID", $ns)
    }
    if (-not $supplierVatNode -or [string]::IsNullOrWhiteSpace($supplierVatNode.'#text')) {
        Write-Host "Validation failed: Supplier VAT number is missing." -ForegroundColor Yellow
        return $false
    }
    if (-not (Test-VatNumberFormat -VatNumber $supplierVatNode.'#text')) {
        Write-Host "Validation failed: Supplier VAT number format is invalid ($($supplierVatNode.'#text'))." -ForegroundColor Yellow
        return $false
    }

    # Extract Customer VAT (BT-48)
    $customerVatNode = $XmlDoc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party/cac:PartyTaxScheme[cac:TaxScheme/cbc:ID='VAT']/cbc:CompanyID", $ns)
    if (-not $customerVatNode) {
        $customerVatNode = $XmlDoc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party/cac:PartyTaxScheme/cbc:CompanyID", $ns)
    }
    if (-not $customerVatNode -or [string]::IsNullOrWhiteSpace($customerVatNode.'#text')) {
        Write-Host "Validation failed: Customer VAT number is missing." -ForegroundColor Yellow
        return $false
    }
    if (-not (Test-VatNumberFormat -VatNumber $customerVatNode.'#text')) {
        Write-Host "Validation failed: Customer VAT number format is invalid ($($customerVatNode.'#text'))." -ForegroundColor Yellow
        return $false
    }
    
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

<#
.SYNOPSIS
  Validates standard VAT calculations and consistency on the XML invoice document.
.DESCRIPTION
  This function loops through all TaxSubtotal elements in the XML to check that:
  1. The calculated tax matches the declared tax amount based on the category percent.
  2. The sum of taxable bases matches the header TaxExclusiveAmount.
  3. TaxExclusiveAmount + TaxAmount = TaxInclusiveAmount.
  4. TaxInclusiveAmount matches the PayableAmount.
.PARAMETER XmlDoc
  The parsed [xml] document of the Peppol invoice.
.RETURN
  True if VAT calculations are consistent, False otherwise.
#>
function Test-InvoiceVat {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [xml]$XmlDoc
    )
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

<#
.SYNOPSIS
  Verifies that a provided token matches the API_TOKEN environment variable.
.DESCRIPTION
  This function compares the given string against the configured API_TOKEN for basic authentication.
.PARAMETER Token
  The token string to verify.
.RETURN
  True if the token is valid, False otherwise.
#>
function Test-AuthToken {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Token
    )
    $validToken = $env:API_TOKEN
    if ([string]::IsNullOrEmpty($validToken)) { return $false }
    return $Token -eq $validToken
}

<#
.SYNOPSIS
  Simulates uploading a generated PDF invoice to a cloud storage location.
.DESCRIPTION
  This function creates a 'cloud_sync' folder adjacent to the output PDF file and copies
  the PDF to it to mock a synchronization workflow.
.PARAMETER PdfPath
  The local filepath of the generated PDF invoice.
#>
function Publish-ToCloud {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$PdfPath
    )
    
    # Simulate uploading to a cloud folder (e.g., OneDrive/SharePoint sync folder)
    $parentDir = Split-Path $PdfPath
    $cloudDir = Join-Path $parentDir "cloud_sync"
    
    if (-not (Test-Path $cloudDir)) { New-Item -ItemType Directory -Path $cloudDir -Force | Out-Null }
    
    Copy-Item -Path $PdfPath -Destination $cloudDir -Force
    Write-Host "   -> Uploaded to Cloud Storage (Simulated at $cloudDir)" -ForegroundColor Cyan
}

<#
.SYNOPSIS
  Starts the core invoice processing loop.
.DESCRIPTION
  This function initializes the iText PDF libraries, connects to the database, and begins
  polling the `invoices` table for new records (status = 'new'). For each new invoice, it:
  1. Validates the XML structure, totals, business rules, and VAT.
  2. Extracts the supplier and customer VAT numbers.
  3. Updates the invoice status to 'processing' and stores the extracted VAT numbers.
  4. Transforms the XML to HTML via XSLT.
  5. Generates a PDF from the HTML using iText.
  6. Copies the PDF to a cloud sync directory.
  7. Updates the invoice status to 'processed'.
.PARAMETER DbHost
  Database host. Defaults to the DB_HOST environment variable.
.PARAMETER DbUser
  Database username. Defaults to the DB_USER environment variable.
.PARAMETER DbPassword
  Database password. Defaults to the DB_PASSWORD environment variable.
.PARAMETER DbDatabase
  Database schema name. Defaults to the DB_DATABASE environment variable.
.PARAMETER ConnectionName
  Symbolic name of the SQL connection. Defaults to 'InvoicesDB'.
.PARAMETER LibPath
  Directory containing iText .NET DLL files. Defaults to '/app/lib'.
.PARAMETER XsltPath
  Path to the XSLT stylesheet for HTML conversion. Defaults to '/app/templates/invoice-transform.xslt'.
.PARAMETER OutputDir
  Directory where generated PDFs will be stored. Defaults to '/app/output'.
.PARAMETER PollingIntervalSeconds
  Polling interval in seconds. Defaults to 5.
#>
function Start-PeppolProcessor {
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DbHost = $env:DB_HOST,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DbUser = $env:DB_USER,

        [Parameter(Mandatory=$false)]
        [string]$DbPassword = $env:DB_PASSWORD,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DbDatabase = $env:DB_DATABASE,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ConnectionName = "InvoicesDB",

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$LibPath = "/app/lib",

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$XsltPath = "/app/templates/invoice-transform.xslt",

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputDir = "/app/output",

        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 3600)]
        [int]$PollingIntervalSeconds = 5
    )

    # Initialize iText and dependency libraries
    Initialize-PeppolPdfLibrary -LibPath $LibPath

    Write-Host "Invoice processing started. Waiting for database to be ready..."
    Start-Sleep -Seconds 15 # Give the database container time to initialize

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
                # Load XML document
                $xmlDoc = [xml]$invoice.peppol_xml

                # 1. Validate
                if (-not (Test-InvoiceTotals -XmlDoc $xmlDoc)) { throw "Validation failed: Totals mismatch." }
                if (-not (Test-InvoiceBusinessRules -XmlDoc $xmlDoc)) { throw "Validation failed: Business rules check failed." }
                if (-not (Test-InvoiceVat -XmlDoc $xmlDoc)) { throw "Validation failed: VAT calculation incorrect." }

                # Extract Supplier and Customer VAT numbers using XML Namespaces
                $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
                $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
                $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')

                # Extract Supplier VAT (BT-31)
                $supplierVatNode = $xmlDoc.SelectSingleNode("//cac:AccountingSupplierParty/cac:Party/cac:PartyTaxScheme[cac:TaxScheme/cbc:ID='VAT']/cbc:CompanyID", $ns)
                if (-not $supplierVatNode) {
                    $supplierVatNode = $xmlDoc.SelectSingleNode("//cac:AccountingSupplierParty/cac:Party/cac:PartyTaxScheme/cbc:CompanyID", $ns)
                }
                $supplierVat = if ($supplierVatNode) { $supplierVatNode.'#text' } else { $null }

                # Extract Customer VAT (BT-48)
                $customerVatNode = $xmlDoc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party/cac:PartyTaxScheme[cac:TaxScheme/cbc:ID='VAT']/cbc:CompanyID", $ns)
                if (-not $customerVatNode) {
                    $customerVatNode = $xmlDoc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party/cac:PartyTaxScheme/cbc:CompanyID", $ns)
                }
                $customerVat = if ($customerVatNode) { $customerVatNode.'#text' } else { $null }

                # 2. Status processing & Save VAT numbers to database
                Update-InvoiceStatus -InvoiceId $invoiceId -Status 'processing' -SupplierVat $supplierVat -CustomerVat $customerVat -ConnectionName $ConnectionName

                # 3. Transform
                $htmlContent = ConvertTo-InvoiceHtml -XmlContent $invoice.peppol_xml -XsltPath $XsltPath
                if (-not $htmlContent) { throw "Transformation to HTML failed." }

                # 4. PDF
                $pdfPath = Join-Path -Path $OutputDir -ChildPath "invoice-$($invoiceId)-$(Get-Date -Format 'yyyyMMddHHmmss').pdf"
                Convert-HtmlToPdf -HtmlContent $htmlContent -OutputPath $pdfPath -BaseUri $OutputDir
                Write-Host "Successfully generated PDF: $pdfPath"

                # Cloud Storage upload (simulated)
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

<#
.SYNOPSIS
  Imports Peppol UBL XML invoices from the filesystem into the MySQL database.
.DESCRIPTION
  This function scans a directory (or takes a single file path) for *.xml files, reads their contents,
  and inserts them as new records in the `invoices` table with status 'new'.
.PARAMETER SourcePath
  The directory containing XML invoices, or a specific XML file path.
.PARAMETER DbHost
  Database host IP or DNS. Defaults to '127.0.0.1'.
.PARAMETER DbUser
  Database username. Defaults to 'root'.
.PARAMETER DbPassword
  Database password. Defaults to empty string.
.PARAMETER DbDatabase
  Database schema name. Defaults to 'invoices_db'.
#>
function Import-PeppolData {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DbHost = "127.0.0.1",

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DbUser = "root",

        [Parameter(Mandatory=$false)]
        [string]$DbPassword = "",

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
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

<#
.SYNOPSIS
  Generates an HTML system report showing invoice processing stats and recent errors.
.DESCRIPTION
  This function queries the database to group invoices by processing status and fetch the 10 most recent error records,
  then compiles this information into a formatted HTML status report.
.PARAMETER DbHost
  Database host. Defaults to the DB_HOST environment variable.
.PARAMETER DbUser
  Database username. Defaults to the DB_USER environment variable.
.PARAMETER DbPassword
  Database password. Defaults to the DB_PASSWORD environment variable.
.PARAMETER DbDatabase
  Database schema name. Defaults to the DB_DATABASE environment variable.
.PARAMETER ReportPath
  Output path where the HTML report will be saved. Defaults to '/app/output/status_report.html'.
#>
function New-PeppolReport {
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DbHost = $env:DB_HOST,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DbUser = $env:DB_USER,

        [Parameter(Mandatory=$false)]
        [string]$DbPassword = $env:DB_PASSWORD,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$DbDatabase = $env:DB_DATABASE,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
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

        $html | Out-File -FilePath $ReportPath
        Write-Host "Report generated at: $ReportPath" -ForegroundColor Green

    } catch {
        Write-Error "Failed to generate report: $($_.Exception.Message)"
    } finally {
        try { Close-SqlConnection -ConnectionName $connectionName } catch {}
    }
}

Export-ModuleMember -Function *