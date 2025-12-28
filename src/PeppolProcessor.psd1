@{
    RootModule = 'PeppolProcessor.psm1'
    ModuleVersion = '1.0'
    GUID = 'a1b2c3d4-e5f6-7890-1234-567890abcdef'
    Author = 'GustB'
    FunctionsToExport = @(
        'Initialize-PeppolPdfLibrary',
        'Connect-Database',
        'Update-InvoiceStatus',
        'Transform-XmlToHtml',
        'Convert-HtmlToPdf',
        'Test-InvoiceTotals',
        'Test-InvoiceBusinessRules',
        'Test-InvoiceVat',
        'Test-AuthToken'
    )
}