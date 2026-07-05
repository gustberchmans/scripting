<#
.SYNOPSIS
  Helper script to import Peppol XML invoices into the MySQL database.
.DESCRIPTION
  This script loads environment variables from the `.env` file (if present) to configure database connection details, 
  imports the 'PeppolProcessor' module, and calls the 'Import-PeppolData' command to parse and insert XML files 
  from the specified directory into the MySQL database with status 'new'.
.PARAMETER Path
  The filesystem path to the XML invoice file or directory containing XML invoice files.
  Defaults to the '../data' folder relative to the script directory.
.PARAMETER DbHost
  Database host IP or DNS. Defaults to the DB_HOST environment variable, or falls back to '127.0.0.1'.
.PARAMETER DbUser
  Database username. Defaults to the DB_USER environment variable, or falls back to 'root'.
.PARAMETER DbPassword
  Database password. Defaults to the DB_PASSWORD environment variable, or falls back to an empty string.
.PARAMETER DbDatabase
  Database schema name. Defaults to the DB_DATABASE environment variable, or falls back to 'invoices_db'.
.EXAMPLE
  pwsh ./Insert-Data.ps1 -Path "../data/valid.xml"
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$Path,

    [Parameter(Mandatory=$false)]
    [string]$DbHost = $env:DB_HOST,

    [Parameter(Mandatory=$false)]
    [string]$DbUser = $env:DB_USER,

    [Parameter(Mandatory=$false)]
    [string]$DbPassword = $env:DB_PASSWORD,

    [Parameter(Mandatory=$false)]
    [string]$DbDatabase = $env:DB_DATABASE
)

# Load .env file if it exists (for local execution environment bootstrap)
$envFile = Join-Path $PSScriptRoot "../.env"
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
        $k, $v = $_.Split('=', 2)
        $k = $k.Trim()
        $v = $v.Trim()
        if (-not (Test-Path "Env:\$k")) { Set-Item -Path "Env:\$k" -Value $v }
    }
}

# Apply default values if neither parameters nor environment variables were set
if ([string]::IsNullOrEmpty($DbHost)) { $DbHost = "127.0.0.1" }
if ([string]::IsNullOrEmpty($DbUser)) { $DbUser = "root" }
if ([string]::IsNullOrEmpty($DbPassword)) { $DbPassword = "" }
if ([string]::IsNullOrEmpty($DbDatabase)) { $DbDatabase = "invoices_db" }

# Assume script is in /src, so default data is in ../data
if ([string]::IsNullOrEmpty($Path)) {
    $Path = Join-Path $PSScriptRoot "../data"
}

# Import Custom Module
Import-Module (Join-Path $PSScriptRoot "PeppolProcessor.psm1") -Force

# Insert data into DB
Import-PeppolData `
    -SourcePath $Path `
    -DbHost $DbHost `
    -DbUser $DbUser `
    -DbPassword $DbPassword `
    -DbDatabase $DbDatabase