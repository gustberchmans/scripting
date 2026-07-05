<#
.SYNOPSIS
  Helper script to generate a status report of Peppol invoice processing.
.DESCRIPTION
  This script loads the 'PeppolProcessor' module and invokes the 'New-PeppolReport' 
  command to query the MySQL database and generate an HTML report containing 
  statistics on processed, error, and new invoices.
.PARAMETER DbHost
  Database host IP or DNS name. Defaults to the DB_HOST environment variable.
.PARAMETER DbUser
  Database username. Defaults to the DB_USER environment variable.
.PARAMETER DbPassword
  Database password. Defaults to the DB_PASSWORD environment variable.
.PARAMETER DbDatabase
  Database schema name. Defaults to the DB_DATABASE environment variable.
.PARAMETER ReportPath
  The destination path for the generated HTML report. Defaults to '/app/output/status_report.html'.
.EXAMPLE
  pwsh ./Get-Report.ps1 -ReportPath "./report.html"
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$DbHost = $env:DB_HOST,

    [Parameter(Mandatory=$false)]
    [string]$DbUser = $env:DB_USER,

    [Parameter(Mandatory=$false)]
    [string]$DbPassword = $env:DB_PASSWORD,

    [Parameter(Mandatory=$false)]
    [string]$DbDatabase = $env:DB_DATABASE,

    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "/app/output/status_report.html"
)

# Import Custom Module
Import-Module (Join-Path $PSScriptRoot "PeppolProcessor.psm1") -Force

# Generate Report
New-PeppolReport `
    -DbHost $DbHost `
    -DbUser $DbUser `
    -DbPassword $DbPassword `
    -DbDatabase $DbDatabase `
    -ReportPath $ReportPath