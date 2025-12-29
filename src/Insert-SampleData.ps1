<#
.SYNOPSIS
  Wrapper script to insert data using the PeppolProcessor module.
  Usage: ./Insert-Data.ps1 [-Path <path-to-xml-or-folder>]
#>

param([string]$Path)

# Load .env file if it exists (for local execution)
$envFile = Join-Path $PSScriptRoot "../.env"
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
        $k, $v = $_.Split('=', 2)
        $k = $k.Trim()
        $v = $v.Trim()
        if (-not (Test-Path "Env:\$k")) { Set-Item -Path "Env:\$k" -Value $v }
    }
}

$dbHost = if ($env:DB_HOST) { $env:DB_HOST } else { "127.0.0.1" }
$dbUser = if ($env:DB_USER) { $env:DB_USER } else { "root" }
$dbPassword = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } else { "" }
$dbDatabase = if ($env:DB_DATABASE) { $env:DB_DATABASE } else { "invoices_db" }

# Assume script is in /src, so data is in ../data
if ([string]::IsNullOrEmpty($Path)) {
    $Path = Join-Path $PSScriptRoot "../data"
}

Import-Module "$PSScriptRoot/PeppolProcessor.psm1" -Force

Import-PeppolData `
    -SourcePath $Path `
    -DbHost $dbHost `
    -DbUser $dbUser `
    -DbPassword $dbPassword `
    -DbDatabase $dbDatabase