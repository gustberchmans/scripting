$libPath = "/app/lib"
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

if (-not (Test-Path $libPath)) { New-Item -Path $libPath -ItemType Directory | Out-Null }

foreach ($name in $packages.Keys) {
    $url = $packages[$name]
    $zipPath = Join-Path $libPath $name
    $extractPath = Join-Path $libPath ($name + "_extract")
    
    Write-Host "Downloading $name..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    
    $allDlls = Get-ChildItem -Path $extractPath -Filter "*.dll" -Recurse
    $groupedDlls = $allDlls | Group-Object Name
    
    foreach ($group in $groupedDlls) {
        # Prefer .NET Standard versions for Linux compatibility
        $bestDll = $group.Group | Where-Object { $_.FullName -match "netstandard" } | Sort-Object FullName -Descending | Select-Object -First 1
        if (-not $bestDll) { $bestDll = $group.Group | Select-Object -First 1 }
        
        $dest = Join-Path $libPath $bestDll.Name
        if (-not (Test-Path $dest)) { Move-Item $bestDll.FullName $dest }
    }
    
    Remove-Item $zipPath -Force
    Remove-Item $extractPath -Recurse -Force
}

Write-Host "iText dependencies installed to $libPath"

# Install Pester module for testing
Write-Host "Installing Pester module..."
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope AllUsers