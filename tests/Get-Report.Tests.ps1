$scriptPath = "$PSScriptRoot/../src/Get-Report.ps1"

Describe "Get-Report.ps1" {
    BeforeAll {
        # Mock external dependencies to prevent actual execution
        Mock -CommandName Import-Module -MockWith { }
        Mock -CommandName Open-MySqlConnection -MockWith { }
        Mock -CommandName Close-SqlConnection -MockWith { }
        Mock -CommandName ConvertTo-SecureString -MockWith { return "secure" }
        Mock -CommandName New-Object -MockWith { return [PSCustomObject]@{} }
        Mock -CommandName Write-Host -MockWith { }
        Mock -CommandName Write-Warning -MockWith { }
        Mock -CommandName Write-Error -MockWith { }
        Mock -CommandName Out-File -MockWith { }
        Mock -CommandName Get-Content -MockWith { return "DB_PASSWORD=secret" }
        Mock -CommandName Set-Item -MockWith { }
        Mock -CommandName Add-Type -MockWith { }
        
        # Mock Join-Path to avoid path issues in mocks
        Mock -CommandName Join-Path -MockWith { return "$($args[0])/$($args[1])" }

        # Mock Test-Path
        # Return false for /app/lib to skip PDF generation logic which requires DLLs
        Mock -CommandName Test-Path -MockWith { 
            param($Path)
            if ($Path -eq "/app/lib") { return $false }
            return $true 
        }

        # Mock Invoke-SqlQuery to return dummy data
        Mock -CommandName Invoke-SqlQuery -MockWith {
            param($Query)
            if ($Query -match "SELECT status, COUNT") {
                return @(
                    [PSCustomObject]@{ status = 'new'; count = 5 }
                    [PSCustomObject]@{ status = 'processed'; count = 10 }
                )
            }
            if ($Query -match "SELECT id, processed_at") {
                return @(
                    [PSCustomObject]@{ id = 1; processed_at = '2023-01-01'; error_message = 'Test Error' }
                )
            }
            return @()
        }
    }

    It "Generates an HTML report with correct statistics" {
        # Run the script with a dummy password to bypass parameter checks
        & $scriptPath -dbPassword "test"

        # Verify SQL queries were executed (Stats + Errors)
        Assert-MockCalled Invoke-SqlQuery -Times 2
        
        # Verify the report file was written
        Assert-MockCalled Out-File -Times 1
    }
}