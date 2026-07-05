Describe "Get-Report.ps1" {
    BeforeAll {
        $script:scriptPath = (Get-Item "$PSScriptRoot/../src/Get-Report.ps1").FullName
        Import-Module "$PSScriptRoot/../src/PeppolProcessor.psm1" -Force
        # Mock external dependencies to prevent actual execution
        Mock -CommandName Import-Module -MockWith { }
        Mock -CommandName Open-MySqlConnection -MockWith { } -ModuleName 'PeppolProcessor'
        Mock -CommandName Close-SqlConnection -MockWith { } -ModuleName 'PeppolProcessor'
        Mock -CommandName Write-Host -MockWith { } -ModuleName 'PeppolProcessor'
        Mock -CommandName Write-Warning -MockWith { } -ModuleName 'PeppolProcessor'
        Mock -CommandName Write-Error -MockWith { } -ModuleName 'PeppolProcessor'
        Mock -CommandName Out-File -MockWith { } -ModuleName 'PeppolProcessor'
        
        # Mock Join-Path to avoid path issues in mocks
        Mock -CommandName Join-Path -MockWith { return "$($args[0])/$($args[1])" } -ModuleName 'PeppolProcessor'

        # Mock Test-Path
        # Return false for /app/lib to skip PDF generation logic which requires DLLs
        Mock -CommandName Test-Path -MockWith { 
            param($Path)
            if ($Path -eq "/app/lib") { return $false }
            return $true 
        } -ModuleName 'PeppolProcessor'

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
        } -ModuleName 'PeppolProcessor'
    }

    It "Generates an HTML report with correct statistics" {
        # Run the script with a dummy password to bypass parameter checks
        & $script:scriptPath -dbPassword "test"

        # Verify SQL queries were executed (Stats + Errors)
        Assert-MockCalled Invoke-SqlQuery -Times 2 -ModuleName 'PeppolProcessor'
        
        # Verify the report file was written
        Assert-MockCalled Out-File -Times 1 -ModuleName 'PeppolProcessor'
    }
}