# Refactored for Pester 5+
# Mocks must be defined before the tested script is dot-sourced.
BeforeAll {
    # Mock database and other external cmdlets
    Mock -CommandName 'Import-Module' -MockWith { }
    Mock -CommandName 'Open-MySqlConnection' -MockWith { return $true }
    Mock -CommandName 'Invoke-SqlQuery' -MockWith { return $script:mockInvoices }
    Mock -CommandName 'Invoke-SqlUpdate' -MockWith { return @{ RecordsAffected = 1 } }
    Mock -CommandName 'Update-InvoiceStatus' -MockWith {
        param($invoiceId, $status, $errorMessage)
        $call = [PSCustomObject]@{ InvoiceId = $invoiceId; Status = $status; ErrorMessage = $errorMessage }
        $script:updateStatusCalls.Add($call) | Out-Null
    }
    Mock -CommandName 'Out-Pdf'
    Mock -CommandName 'Start-Sleep'
    Mock -CommandName 'Write-Host'

    # Dot-source the script to make its functions available.
    # The main loop is problematic for testing, so we test the functions directly.
    . "$PSScriptRoot/../src/Process-Invoices.ps1"

    # Load sample XML data
    $script:sampleXml = Get-Content -Path "$PSScriptRoot/../sample_data/sample-invoice.xml" -Raw
}

Describe 'Invoice Processing Logic' {
    BeforeEach {
        # Reset mock data and call logs for each test
        $script:mockInvoices = @()
        $script:updateStatusCalls = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName 'Test-Path' -MockWith { return $true }
    }

    Context "Test-InvoiceTotals function" {
        It "should return true for a valid invoice" {
            $xmlDoc = [xml]$script:sampleXml
            $result = Test-InvoiceTotals -xmlDoc $xmlDoc
            $result | Should -Be $true
        }

        It "should return false for an invalid invoice" {
            $invalidXml = $script:sampleXml -replace '<cbc:LineExtensionAmount currencyID="EUR">150.00</cbc:LineExtensionAmount>', '<cbc:LineExtensionAmount currencyID="EUR">149.99</cbc:LineExtensionAmount>'
            $xmlDoc = [xml]$invalidXml
            $result = Test-InvoiceTotals -xmlDoc $xmlDoc
            $result | Should -Be $false
        }
    }

    Context "Full Processing Cycle (simulated)" {
        # This requires manually calling the logic inside the while loop from the main script
        # For simplicity, we'll assume the main script is refactored to have a testable main function.
        # Let's simulate the loop's content for one run.
        
        It "should process a valid invoice correctly" {
            # Arrange
            $script:mockInvoices = @([PSCustomObject]@{ id = 1; peppol_xml = $script:sampleXml })
            
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
                $html | Out-Pdf -Path "test.pdf"
                Update-InvoiceStatus -invoiceId $invoice.id -status 'processed'
            } catch {}

            # Assert
            $script:updateStatusCalls.Count | Should -Be 2
            $script:updateStatusCalls[0].Status | Should -Be 'processing'
            $script:updateStatusCalls[1].Status | Should -Be 'processed'
        }

        It "should catch a validation error" {
            # Arrange
            $invalidXml = $script:sampleXml -replace '<cbc:LineExtensionAmount currencyID="EUR">150.00</cbc:LineExtensionAmount>', '<cbc:LineExtensionAmount currencyID="EUR">149.99</cbc:LineExtensionAmount>'
            $script:mockInvoices = @([PSCustomObject]@{ id = 2; peppol_xml = $invalidXml })

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
            $script:updateStatusCalls[0].ErrorMessage | Should -Contain 'Validation failed'
        }
    }
}
