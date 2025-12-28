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

# Import Custom Module
Import-Module "$PSScriptRoot/PeppolProcessor.psd1" -Force

# --- Main Processing Loop ---

# Initialize Libraries
try {
    Initialize-PeppolPdfLibrary -LibPath "/app/lib"
} catch {
    Write-Host "FATAL: Could not load iText dependencies. Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($MyInvocation.InvocationName -ne '.') {
Write-Host "Invoice processing script started. Waiting for database to be ready..."
Start-Sleep -Seconds 15 # Give the database time to initialize

try {
    Import-Module SimplySql
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
            $htmlContent = ConvertTo-InvoiceHtml -XmlContent $invoice.peppol_xml -XsltPath $xsltPath
            if (-not $htmlContent) {
                throw "Transformation to HTML failed or produced empty content."
            }

            # 4. Generate PDF
            $pdfPath = Join-Path -Path $outputDir -ChildPath "invoice-$($invoiceId)-$(Get-Date -Format 'yyyyMMddHHmmss').pdf"
            
            Convert-HtmlToPdf -htmlContent $htmlContent -outputPath $pdfPath -baseUri $outputDir

            Write-Host "Successfully generated PDF: $pdfPath"

            # Extra: Cloud Integration
            Publish-ToCloud -PdfPath $pdfPath

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
