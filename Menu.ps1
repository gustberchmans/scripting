<#
.SYNOPSIS
  CLI Control Panel for the Peppol Invoice Processing System.
.DESCRIPTION
  This script provides an interactive menu to control and test the Peppol invoicing tool,
  including running tests, seeding data, checking logs, and managing docker containers.
#>

# Ensure we are in the script's directory
$scriptDir = Split-Path $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = Get-Location }
Set-Location $scriptDir

function Show-Menu {
    Clear-Host
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "       Peppol Processing CLI Control Panel               " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " 1. Run Pester Unit & Integration Tests                  "
    Write-Host " 2. Seed Database with Sample Invoices (Insert-Data)     "
    Write-Host " 3. View System Logs (Real-time polling logs)            "
    Write-Host " 4. Generate & View Status Report (HTML)                 "
    Write-Host " 5. Reset & Rebuild Docker Containers (docker-compose)   "
    Write-Host " 6. Exit                                                 "
    Write-Host "=========================================================" -ForegroundColor Cyan
}

do {
    Show-Menu
    $choice = Read-Host "Select an option [1-6]"
    switch ($choice) {
        "1" {
            Write-Host "Running Pester tests inside container..." -ForegroundColor Yellow
            docker-compose exec app pwsh -c "Invoke-Pester /app/tests/Process-Invoices.Tests.ps1 -Output Detailed"
            Read-Host "`nPress Enter to continue"
        }
        "2" {
            Write-Host "Seeding database with sample XML invoices..." -ForegroundColor Yellow
            docker-compose exec app pwsh /app/src/Insert-Data.ps1
            Read-Host "`nPress Enter to continue"
        }
        "3" {
            Write-Host "Streaming real-time logs (Press Ctrl+C to exit logs)..." -ForegroundColor Yellow
            docker-compose logs -f app
            Read-Host "`nPress Enter to continue"
        }
        "4" {
            Write-Host "Generating status report..." -ForegroundColor Yellow
            docker-compose exec app pwsh /app/src/Get-Report.ps1
            $reportPath = Join-Path $scriptDir "output/status_report.html"
            if (Test-Path $reportPath) {
                Write-Host "Report generated at output/status_report.html" -ForegroundColor Green
                # Open browser if xdg-open exists (Linux)
                if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
                    Start-Process xdg-open -ArgumentList "`"$reportPath`""
                } else {
                    Write-Host "Please open the report file at: $reportPath" -ForegroundColor Yellow
                }
            } else {
                Write-Error "Report file not found."
            }
            Read-Host "`nPress Enter to continue"
        }
        "5" {
            Write-Host "Rebuilding and restarting docker containers..." -ForegroundColor Yellow
            docker-compose down -v
            docker-compose up --build -d
            Read-Host "`nPress Enter to continue"
        }
        "6" {
            Write-Host "Exiting. Goodbye!" -ForegroundColor Green
            break
        }
        default {
            Write-Host "Invalid option. Please select 1-6." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
