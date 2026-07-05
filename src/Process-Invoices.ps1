<#
.SYNOPSIS
  Entry point bootstrapper for the Peppol XML Invoice Processor.
.DESCRIPTION
  This script acts as the main entry point to initiate the background polling loop 
  for Peppol XML invoice processing. It imports the 'PeppolProcessor' module, 
  which encapsulates all database, validation, and PDF rendering operations.
  
  ARCHITECTURAL DESIGN RATIONALE:
  - Separation of Concerns: Core logic is packaged into a reusable PowerShell script module (.psm1).
    This allows developers and administrators to load and use module commands independently,
    conduct unit and integration testing via Pester, and run automated operations in container tasks.
  - Thin Bootstrapper: This entrypoint script acts as a simple coordinator that handles 
    bootstrapping the environment, loading dependencies, and calling the main module loop.
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
.EXAMPLE
  pwsh ./Process-Invoices.ps1 -PollingIntervalSeconds 10
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
    [string]$ConnectionName = "InvoicesDB",

    [Parameter(Mandatory=$false)]
    [string]$LibPath = "/app/lib",

    [Parameter(Mandatory=$false)]
    [string]$XsltPath = "/app/templates/invoice-transform.xslt",

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "/app/output",

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 3600)]
    [int]$PollingIntervalSeconds = 5
)

# Import Custom Module
Import-Module (Join-Path $PSScriptRoot "PeppolProcessor.psm1") -Force

# Start the processor with passed parameters
Start-PeppolProcessor `
    -DbHost $DbHost `
    -DbUser $DbUser `
    -DbPassword $DbPassword `
    -DbDatabase $DbDatabase `
    -ConnectionName $ConnectionName `
    -LibPath $LibPath `
    -XsltPath $XsltPath `
    -OutputDir $OutputDir `
    -PollingIntervalSeconds $PollingIntervalSeconds
