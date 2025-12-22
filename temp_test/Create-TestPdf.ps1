<#
.SYNOPSIS
  Creates a PDF invoice based on user input.
.DESCRIPTION
  This script prompts the user for basic invoice data, generates an XML,
  transforms it to HTML using an XSLT template, and then converts the HTML
  to a PDF file using iText 7.
#>
function Transform-XmlToHtml {
    param(
        [string]$xmlContent,
        [string]$xsltPath
    )
    
    if (-not (Test-Path $xsltPath)) {
        throw "XSLT template not found at: $xsltPath"
    }

    $xslt = New-Object System.Xml.Xsl.XslCompiledTransform;
    $xslt.Load($xsltPath)

    $xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xmlContent))
    
    $stringWriter = New-Object System.IO.StringWriter
    $xslt.Transform($xmlReader, $null, $stringWriter)
    
    return $stringWriter.ToString()
}

function Ensure-iTextDependencies {
    param(
        [string]$libPath
    )

    $requiredDlls = @(
        "BouncyCastle.Crypto.dll",
        "Common.Logging.dll",
        "Common.Logging.Core.dll",
        "System.Drawing.Common.dll",
        "Microsoft.Extensions.DependencyModel.dll",
        "Microsoft.DotNet.PlatformAbstractions.dll",
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

    $missingDlls = $requiredDlls | ForEach-Object {
        if (-not (Test-Path (Join-Path -Path $libPath -ChildPath $_))) {
            $_
        }
    }

    if ($missingDlls.Count -gt 0) {
        Write-Host "iText dependencies not found. Downloading..." -ForegroundColor Yellow
        
        $packages = @{
            "itext7.7.1.15.nupkg" = "https://www.nuget.org/api/v2/package/itext7/7.1.15";
            "itext7.pdfhtml.3.0.1.nupkg" = "https://www.nuget.org/api/v2/package/itext7.pdfhtml/3.0.1";
            "Portable.BouncyCastle.1.8.9.nupkg" = "https://www.nuget.org/api/v2/package/Portable.BouncyCastle/1.8.9";
            "Common.Logging.3.4.1.nupkg" = "https://www.nuget.org/api/v2/package/Common.Logging/3.4.1";
            "Common.Logging.Core.3.4.1.nupkg" = "https://www.nuget.org/api/v2/package/Common.Logging.Core/3.4.1";
            "System.Drawing.Common.5.0.2.nupkg" = "https://www.nuget.org/api/v2/package/System.Drawing.Common/5.0.2";
            "Microsoft.Extensions.DependencyModel.2.1.0.nupkg" = "https://www.nuget.org/api/v2/package/Microsoft.Extensions.DependencyModel/2.1.0";
            "Microsoft.DotNet.PlatformAbstractions.2.1.0.nupkg" = "https://www.nuget.org/api/v2/package/Microsoft.DotNet.PlatformAbstractions/2.1.0"
        }

        # Create the lib directory if it doesn't exist
        if (-not (Test-Path $libPath)) {
            New-Item -Path $libPath -ItemType Directory | Out-Null
        }

        foreach ($name in $packages.Keys) {
            $url = $packages[$name]
            $zipPath = Join-Path -Path $libPath -ChildPath $name
            # Unique extraction path to avoid conflicts
            $extractPath = Join-Path -Path $libPath -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($name) + "_" + [System.Guid]::NewGuid().ToString().Substring(0,8))

            try {
                Write-Host "Downloading $name..."
                Invoke-WebRequest -Uri $url -OutFile $zipPath
                Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

                # Find all DLLs and group by name
                $allDlls = Get-ChildItem -Path $extractPath -Filter "*.dll" -Recurse
                $groupedDlls = $allDlls | Group-Object Name

                foreach ($group in $groupedDlls) {
                    # Prefer .NET Standard versions (compatible with PowerShell Core/Linux)
                    $bestDll = $group.Group | Where-Object { $_.FullName -match "netstandard" } | Sort-Object FullName -Descending | Select-Object -First 1
                    
                    if (-not $bestDll) {
                        $bestDll = $group.Group | Select-Object -First 1
                    }
                    
                    $destination = Join-Path -Path $libPath -ChildPath $bestDll.Name
                    if (-not (Test-Path $destination)) {
                        Move-Item -Path $bestDll.FullName -Destination $destination
                    }
                }

                Write-Host "$name processed successfully." -ForegroundColor Green
            }
            catch {
                Write-Host "Error downloading or extracting $($name): $($_.Exception.Message)" -ForegroundColor Red
            }
            finally {
                if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
                if (Test-Path $extractPath) { Remove-Item -Path $extractPath -Recurse -Force }
            }
        }

        # Final check
        $finalMissingDlls = $requiredDlls | ForEach-Object { if (-not (Test-Path (Join-Path -Path $libPath -ChildPath $_))) { $_ } }
        if ($finalMissingDlls.Count -eq 0) {
            Write-Host "All iText dependencies installed successfully." -ForegroundColor Green
        } else {
            Write-Host "Not all dependencies could be installed. Missing files: $($finalMissingDlls -join ', ')" -ForegroundColor Red
            exit
        }
    }
}

# --- Main Script ---

Write-Host "--- PDF Generation Test Script ---" -ForegroundColor Cyan

# 0. Check and install iText dependencies
$libPath = Join-Path -Path $PSScriptRoot -ChildPath "lib"
Ensure-iTextDependencies -libPath $libPath

# 1. Prompt for user data
$invoiceId = Read-Host "Enter invoice number (e.g., TEST-001)"
$customer = Read-Host "Enter customer name"
$item = Read-Host "Enter item description"
$amount = Read-Host "Enter amount (e.g., 123.45)"

# 2. Generate XML from data
$xmlString = @"
<?xml version="1.0" encoding="UTF-8"?>
<Invoice>
    <InvoiceID>$($invoiceId)</InvoiceID>
    <Customer>$($customer)</Customer>
    <Item>$($item)</Item>
    <Amount>$($amount)</Amount>
</Invoice>
"@

Write-Host "XML structure created..."

# 3. Transform XML to HTML
$xsltTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath "Test-Template.xslt"
try {
    $htmlContent = Transform-XmlToHtml -xmlContent $xmlString -xsltPath $xsltTemplatePath
    Write-Host "HTML transformation successful..."
}
catch {
    Write-Host "Error transforming XML to HTML: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 4. Convert HTML to PDF using iText
$pdfPath = Join-Path -Path $PSScriptRoot -ChildPath "TestFactuur-$($invoiceId).pdf"

try {
    # Register the CodePages encoding provider for Linux support
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)

    # Load the required assemblies
    Add-Type -Path "$libPath/BouncyCastle.Crypto.dll"
    Add-Type -Path "$libPath/Common.Logging.Core.dll"
    Add-Type -Path "$libPath/Common.Logging.dll"
    Add-Type -Path "$libPath/System.Drawing.Common.dll"
    Add-Type -Path "$libPath/Microsoft.DotNet.PlatformAbstractions.dll"
    Add-Type -Path "$libPath/Microsoft.Extensions.DependencyModel.dll"
    Add-Type -Path "$libPath/itext.io.dll"
    Add-Type -Path "$libPath/itext.kernel.dll"
    Add-Type -Path "$libPath/itext.layout.dll"
    Add-Type -Path "$libPath/itext.forms.dll"
    Add-Type -Path "$libPath/itext.pdfa.dll"
    Add-Type -Path "$libPath/itext.sign.dll"
    Add-Type -Path "$libPath/itext.styledxmlparser.dll"
    Add-Type -Path "$libPath/itext.svg.dll"
    Add-Type -Path "$libPath/itext.barcodes.dll"
    Add-Type -Path "$libPath/itext.html2pdf.dll"
    
    $pdfWriter = [iText.Kernel.Pdf.PdfWriter]::new($pdfPath)
    $pdfDocument = [iText.Kernel.Pdf.PdfDocument]::new($pdfWriter)
    $pdfDocument.SetDefaultPageSize([iText.Kernel.Geom.PageSize]::A4)

    $converterProperties = [iText.Html2pdf.ConverterProperties]::new()
    $converterProperties.SetBaseUri($PSScriptRoot)
    
    [iText.Html2Pdf.HtmlConverter]::ConvertToPdf($htmlContent, $pdfDocument, $converterProperties)
    $pdfDocument.Close()
    Write-Host "PDF successfully created at: $pdfPath" -ForegroundColor Green
}
catch {
    Write-Host "Error creating PDF with iText: $($_.Exception.Message)" -ForegroundColor Red
    $ex = $_.Exception
    while ($ex.InnerException) {
        $ex = $ex.InnerException
        Write-Host "Detailed error: $($ex.Message)" -ForegroundColor Red
    }
    
    # Fallback to saving HTML
    $htmlPath = Join-Path -Path $PSScriptRoot -ChildPath "TestFactuur-$($invoiceId).html"
    $htmlContent | Out-File -FilePath $htmlPath -Encoding utf8
    Write-Host "As a fallback, the HTML file has been saved to: $htmlPath" -ForegroundColor Cyan
}

Write-Host "--- Script finished ---" -ForegroundColor Cyan
