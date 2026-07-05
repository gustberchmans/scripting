# Refactored for Pester 5+
# Mocks must be defined before the tested script is dot-sourced.
BeforeAll {
    # Mock database and other external cmdlets
    Mock -CommandName 'Add-Type' -MockWith { }
    Mock -CommandName 'Open-MySqlConnection' -MockWith { return $true }
    Mock -CommandName 'Invoke-SqlQuery' -MockWith { return $script:mockInvoices }
    Mock -CommandName 'Invoke-SqlUpdate' -MockWith { return @{ RecordsAffected = 1 } }
    Mock -CommandName 'Start-Sleep'
    Mock -CommandName 'Write-Host'

    # Import the module to make functions available for testing
    Import-Module "$PSScriptRoot/../src/PeppolProcessor.psd1" -Force

    # Mock module functions to override them
    Mock -CommandName 'Update-InvoiceStatus' -MockWith {
        param($InvoiceId, $Status, $ErrorMessage, $SupplierVat, $CustomerVat, $ConnectionName)
        $call = [PSCustomObject]@{ 
            InvoiceId = $InvoiceId 
            Status = $Status 
            ErrorMessage = $ErrorMessage 
            SupplierVat = $SupplierVat 
            CustomerVat = $CustomerVat 
        }
        $script:updateStatusCalls.Add($call) | Out-Null
    }
    Mock -CommandName 'Convert-HtmlToPdf'

    # Load sample XML data
    $script:dataPath = "$PSScriptRoot/../data"
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
            @{ Name="Valid Credit Note"; File="credit-note.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Negative Price"; File="invalid-negative-price.xml"; ExpectTotals=$true; ExpectRules=$false; ExpectVat=$true }
            @{ Name="Invalid Negative Quantity"; File="invalid-negative-quantity.xml"; ExpectTotals=$true; ExpectRules=$false; ExpectVat=$true }
            @{ Name="Valid Zero Invoice"; File="valid-zero-invoice.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Negative Totals"; File="invalid-negative-totals.xml"; ExpectTotals=$false; ExpectRules=$false; ExpectVat=$true }
            @{ Name="Invalid Zero Totals"; File="invalid-zero-totals.xml"; ExpectTotals=$false; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Valid Zero VAT"; File="valid-zero-vat.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$true }
            @{ Name="Invalid Negative VAT"; File="invalid-negative-vat.xml"; ExpectTotals=$true; ExpectRules=$false; ExpectVat=$false }
            @{ Name="Invalid Zero VAT"; File="invalid-zero-vat.xml"; ExpectTotals=$true; ExpectRules=$true; ExpectVat=$false }
            @{ Name="Invalid Missing VAT"; File="invalid-missing-vat.xml"; ExpectTotals=$true; ExpectRules=$false; ExpectVat=$true }
            @{ Name="Invalid VAT Format"; File="invalid-vat-format.xml"; ExpectTotals=$true; ExpectRules=$false; ExpectVat=$true }
        )

        It "Validation checks for <Name>" -TestCases $testCases {
            param($Name, $File, $ExpectTotals, $ExpectRules, $ExpectVat)
            
            $path = Join-Path $script:dataPath $File
            $content = Get-Content $path -Raw
            $xml = [xml]$content

            Test-InvoiceTotals -xmlDoc $xml | Should -Be $ExpectTotals
            Test-InvoiceBusinessRules -xmlDoc $xml | Should -Be $ExpectRules
            Test-InvoiceVat -xmlDoc $xml | Should -Be $ExpectVat
        }
    }

    Context "VAT Number Format Validation" {
        It "should validate correct NL VAT numbers" {
            Test-VatNumberFormat -VatNumber "NL123456789B01" | Should -Be $true
            Test-VatNumberFormat -VatNumber "nl123456789b01" | Should -Be $true
            Test-VatNumberFormat -VatNumber "NL-123.456.789-B01" | Should -Be $true
        }

        It "should validate correct BE VAT numbers" {
            Test-VatNumberFormat -VatNumber "BE0123456789" | Should -Be $true
            Test-VatNumberFormat -VatNumber "be0123456789" | Should -Be $true
            Test-VatNumberFormat -VatNumber "BE 0123.456.789" | Should -Be $true
        }

        It "should validate correct EU VAT numbers" {
            Test-VatNumberFormat -VatNumber "DE123456789" | Should -Be $true
            Test-VatNumberFormat -VatNumber "FRXX123456789" | Should -Be $true
        }

        It "should reject invalid VAT formats" {
            Test-VatNumberFormat -VatNumber "" | Should -Be $false
            Test-VatNumberFormat -VatNumber "123456789" | Should -Be $false
            Test-VatNumberFormat -VatNumber "N123456789B01" | Should -Be $false
            Test-VatNumberFormat -VatNumber "INVALIDVAT" | Should -Be $false
        }
    }

    Context "Full Processing Cycle (simulated)" {
        # This requires manually calling the logic inside the while loop from the main script
        # For simplicity, we'll assume the main script is refactored to have a testable main function.
        # Let's simulate the loop's content for one run.
        
        It "should process a valid invoice correctly" {
            # Arrange
            $validXml = Get-Content (Join-Path $script:dataPath "valid.xml") -Raw
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
                Update-InvoiceStatus -InvoiceId $invoice.id -Status 'processing'
                $html = ConvertTo-InvoiceHtml -XmlContent $invoice.peppol_xml -XsltPath "$PSScriptRoot/../templates/invoice-transform.xslt"
                Convert-HtmlToPdf -htmlContent $html -outputPath "test.pdf" -baseUri "/tmp"
                Update-InvoiceStatus -InvoiceId $invoice.id -Status 'processed'
            } catch {}

            # Assert
            $script:updateStatusCalls.Count | Should -Be 2
            $script:updateStatusCalls[0].Status | Should -Be 'processing'
            $script:updateStatusCalls[1].Status | Should -Be 'processed'
        }

        It "should catch a validation error" {
            # Arrange
            $invalidXmlContent = Get-Content (Join-Path $script:dataPath "invalid-totals.xml") -Raw
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
                 Update-InvoiceStatus -InvoiceId $invoice.id -Status 'error' -ErrorMessage $_.Exception.Message
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

    Context "Cloud Integration" {
        It "Publish-ToCloud should create directory and copy file" {
            Mock -CommandName Test-Path -MockWith { return $false } -ModuleName 'PeppolProcessor'
            Mock -CommandName New-Item -MockWith { } -ModuleName 'PeppolProcessor'
            Mock -CommandName Copy-Item -MockWith { } -ModuleName 'PeppolProcessor'
            
            Publish-ToCloud -PdfPath "/app/output/test.pdf"
            
            Assert-MockCalled New-Item -Times 1 -ParameterFilter { $Path -match "cloud_sync" -and $ItemType -eq "Directory" } -ModuleName 'PeppolProcessor'
            Assert-MockCalled Copy-Item -Times 1 -ParameterFilter { $Path -eq "/app/output/test.pdf" -and $Destination -match "cloud_sync" } -ModuleName 'PeppolProcessor'
        }
    }

    Context "VAT Number Extraction" {
        It "should extract supplier and customer VAT numbers from Peppol XML" {
            # Arrange
            $validXml = Get-Content (Join-Path $script:dataPath "valid.xml") -Raw
            [xml]$xmlDoc = $validXml
            $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
            $ns.AddNamespace('cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2')
            $ns.AddNamespace('cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2')
            
            # Supplier Party
            $supplierParty = $xmlDoc.SelectSingleNode("//cac:AccountingSupplierParty/cac:Party", $ns)
            $supplierTaxScheme = $xmlDoc.CreateElement("cac", "PartyTaxScheme", $ns.LookupNamespace("cac"))
            $supplierCompanyId = $xmlDoc.CreateElement("cbc", "CompanyID", $ns.LookupNamespace("cbc"))
            $supplierCompanyId.InnerText = "NL123456789B01"
            $supplierTaxScheme.AppendChild($supplierCompanyId) | Out-Null
            $supplierParty.AppendChild($supplierTaxScheme) | Out-Null

            # Customer Party
            $customerParty = $xmlDoc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party", $ns)
            $customerTaxScheme = $xmlDoc.CreateElement("cac", "PartyTaxScheme", $ns.LookupNamespace("cac"))
            $customerCompanyId = $xmlDoc.CreateElement("cbc", "CompanyID", $ns.LookupNamespace("cbc"))
            $customerCompanyId.InnerText = "NL987654321B01"
            $customerTaxScheme.AppendChild($customerCompanyId) | Out-Null
            $customerParty.AppendChild($customerTaxScheme) | Out-Null

            $script:mockInvoices = @([PSCustomObject]@{ id = 100; peppol_xml = $xmlDoc.OuterXml })

            # Act
            $invoice = $script:mockInvoices[0]
            $supplierVat = $null
            $customerVat = $null
            try {
                $doc = [xml]$invoice.peppol_xml
                $supplierVatNode = $doc.SelectSingleNode("//cac:AccountingSupplierParty/cac:Party/cac:PartyTaxScheme/cbc:CompanyID", $ns)
                $supplierVat = if ($supplierVatNode) { $supplierVatNode.'#text' } else { $null }

                $customerVatNode = $doc.SelectSingleNode("//cac:AccountingCustomerParty/cac:Party/cac:PartyTaxScheme/cbc:CompanyID", $ns)
                $customerVat = if ($customerVatNode) { $customerVatNode.'#text' } else { $null }

                Update-InvoiceStatus -InvoiceId $invoice.id -Status 'processing' -SupplierVat $supplierVat -CustomerVat $customerVat
            } catch {}

            # Assert
            $script:updateStatusCalls.Count | Should -Be 1
            $script:updateStatusCalls[0].InvoiceId | Should -Be 100
            $script:updateStatusCalls[0].Status | Should -Be 'processing'
            $script:updateStatusCalls[0].SupplierVat | Should -Be "NL123456789B01"
            $script:updateStatusCalls[0].CustomerVat | Should -Be "NL987654321B01"
        }
    }
}
