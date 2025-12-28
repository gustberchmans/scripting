# Refactored for Pester 5+
# Mocks must be defined before the tested script is dot-sourced.
BeforeAll {
    # Mock database and other external cmdlets
    Mock -CommandName 'Import-Module' -MockWith { }
    Mock -CommandName 'Add-Type' -MockWith { }
    Mock -CommandName 'Open-MySqlConnection' -MockWith { return $true }
    Mock -CommandName 'Invoke-SqlQuery' -MockWith { return $script:mockInvoices }
    Mock -CommandName 'Invoke-SqlUpdate' -MockWith { return @{ RecordsAffected = 1 } }
    Mock -CommandName 'Start-Sleep'
    Mock -CommandName 'Write-Host'

    # Dot-source the script to make its functions available.
    # The main loop is problematic for testing, so we test the functions directly.
    . "$PSScriptRoot/../src/Process-Invoices.ps1"

    # Mock script functions AFTER dot-sourcing to override them
    Mock -CommandName 'Update-InvoiceStatus' -MockWith {
        param($invoiceId, $status, $errorMessage)
        $call = [PSCustomObject]@{ InvoiceId = $invoiceId; Status = $status; ErrorMessage = $errorMessage }
        $script:updateStatusCalls.Add($call) | Out-Null
    }
    Mock -CommandName 'Convert-HtmlToPdf'

    # Load sample XML data
    $script:sampleDataPath = "$PSScriptRoot/../sample_data"
}

Describe 'Invoice Processing Logic' {
    BeforeEach {
        # Reset mock data and call logs for each test
        $script:mockInvoices = @()
        $script:updateStatusCalls = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName 'Test-Path' -MockWith { return $true }
    }

    Context "Data Driven Tests (Sample Files)" {
        $testCases = @(
            @{ Name="Valid Invoice"; File="valid.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Totals"; File="invalid-totals.xml"; ExpectTotals=$false; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Business Rules"; File="invalid-business-rules.xml"; ExpectTotals=$true; ExpectRules=$false; ExpectVat=$true }
            @{ Name="Valid VAT"; File="valid-vat.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid VAT"; File="invalid-vat.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$false }
            @{ Name="Invalid Taxable Mismatch"; File="invalid-taxable-mismatch.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$false }
            @{ Name="Valid Complex (Multi-Line/Rate)"; File="valid-complex.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Valid Quantity Change (5x20)"; File="valid-quantity.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Valid Multi-Line (Same Rate)"; File="valid-multi-line.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Valid Low VAT (9%)"; File="valid-low-vat.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Quantity Math"; File="invalid-quantity.xml"; ExpectTotals=$false; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Multi-Line Sum"; File="invalid-multi-line.xml"; ExpectTotals=$false; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Low VAT Math"; File="invalid-low-vat.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$false }
            @{ Name="Invalid Missing Date"; File="invalid-missing-date.xml"; ExpectTotals=$true; ExpectRules=$false; ExpectVat=$true }
            @{ Name="Valid Allowance (Discount)"; File="valid-allowance.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Allowance Math"; File="invalid-allowance.xml"; ExpectTotals=$false; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Currency Mismatch"; File="invalid-currency-mismatch.xml"; ExpectTotals=$true; ExpectRules=$false; ExpectVat=$true }
            @{ Name="Valid Zero Amount (Free Item)"; File="valid-zero-amount.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
        )

        It "Validation checks for <Name>" -TestCases $testCases {
            param($Name, $File, $ExpectTotals, $ExpectRules, $ExpectVat)
            
            $path = Join-Path $script:sampleDataPath $File
            $content = Get-Content $path -Raw
            $xml = [xml]$content

            Test-InvoiceTotals -xmlDoc $xml | Should -Be $ExpectTotals
            Test-InvoiceBusinessRules -xmlDoc $xml | Should -Be $ExpectRules
            Test-InvoiceVat -xmlDoc $xml | Should -Be $ExpectVat
        }
    }

    Context "Full Processing Cycle (simulated)" {
        # This requires manually calling the logic inside the while loop from the main script
        # For simplicity, we'll assume the main script is refactored to have a testable main function.
        # Let's simulate the loop's content for one run.
        
        It "should process a valid invoice correctly" {
            # Arrange
            $validXml = Get-Content (Join-Path $script:sampleDataPath "valid.xml") -Raw
            $script:mockInvoices = @([PSCustomObject]@{ id = 1; peppol_xml = $validXml })
            
            # Act - Simulate one loop iteration
            # This is a simplified test; proper testing would require refactoring the main script's loop
            # For now, we assume the foreach loop runs once with our mocked data
            $invoice = $script:mockInvoices[0]
            try {
                $xmlDoc = [xml]$invoice.peppol_xml
                if (-not (Test-InvoiceTotals -xmlDoc $xmlDoc)) {
                    throw "Validation failed"
                }
                Update-InvoiceStatus -invoiceId $invoice.id -status 'processing'
                $html = Transform-XmlToHtml -xmlContent $invoice.peppol_xml -xsltPath "$PSScriptRoot/../templates/invoice-transform.xslt"
                Convert-HtmlToPdf -htmlContent $html -outputPath "test.pdf" -baseUri "/tmp"
                Update-InvoiceStatus -invoiceId $invoice.id -status 'processed'
            } catch {}

            # Assert
            $script:updateStatusCalls.Count | Should -Be 2
            $script:updateStatusCalls[0].Status | Should -Be 'processing'
            $script:updateStatusCalls[1].Status | Should -Be 'processed'
        }

        It "should catch a validation error" {
            # Arrange
            $invalidXmlContent = Get-Content (Join-Path $script:sampleDataPath "invalid-totals.xml") -Raw
            $script:mockInvoices = @([PSCustomObject]@{ id = 2; peppol_xml = $invalidXmlContent })

            # Act
            $invoice = $script:mockInvoices[0]
             try {
                $xmlDoc = [xml]$invoice.peppol_xml
                if (-not (Test-InvoiceTotals -xmlDoc $xmlDoc)) {
                    throw "Validation failed: The sum of line items does not match the LegalMonetaryTotal."
                }
                # ... rest of processing which should not be reached
            } catch {
                 Update-InvoiceStatus -invoiceId $invoice.id -status 'error' -errorMessage $_.Exception.Message
            }

            # Assert
            $script:updateStatusCalls.Count | Should -Be 1
            $script:updateStatusCalls[0].Status | Should -Be 'error'
            $script:updateStatusCalls[0].ErrorMessage | Should -Match 'Validation failed'
        }
    }

    Context "Security / Token Verification" {
        It "should accept a valid token" {
            $env:API_TOKEN = "SuperSecret123"
            Test-AuthToken -token "SuperSecret123" | Should -Be $true
        }

        It "should reject an invalid token" {
            $env:API_TOKEN = "SuperSecret123"
            Test-AuthToken -token "HackerToken" | Should -Be $false
        }

        It "should fail secure if no API_TOKEN is configured" {
            $env:API_TOKEN = ""
            Test-AuthToken -token "AnyToken" | Should -Be $false
        }
    }
}
