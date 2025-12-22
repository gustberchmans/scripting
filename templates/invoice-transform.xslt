<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
    xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
    xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2">
    <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID>
    <cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID>
    <cbc:ID>{INVOICE_ID}</cbc:ID>
    <cbc:IssueDate>{INVOICE_BILL_DATE}</cbc:IssueDate>
    <cbc:DueDate>{INVOICE_DUE_DATE}</cbc:DueDate>
    <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
    <cbc:DocumentCurrencyCode>{CURRENCY_CODE}</cbc:DocumentCurrencyCode>
    <cbc:BuyerReference>{CLIENT_ID}</cbc:BuyerReference>
    <cac:AccountingSupplierParty>
        <cac:Party>
            <cbc:EndpointID schemeID="0088">{COMPANY_ELECTRONIC_ADDRESS}</cbc:EndpointID>
            <cac:PartyIdentification>
                <cbc:ID>{COMPANY_VAT_NUMBER}</cbc:ID>
            </cac:PartyIdentification>
            <cac:PartyName>
                <cbc:Name>{COMPANY_NAME}</cbc:Name>
            </cac:PartyName>
            <cac:PostalAddress>
                <cbc:StreetName>{COMPANY_STREET_NAME}</cbc:StreetName>
                <cbc:CityName>{COMPANY_CITY_NAME}</cbc:CityName>
                <cbc:PostalZone>{COMPANY_ZIP}</cbc:PostalZone>
                <cac:Country>
                    <cbc:IdentificationCode>{COMPANY_COUNTRY_CODE}</cbc:IdentificationCode>
                </cac:Country>
            </cac:PostalAddress>
            <cac:PartyTaxScheme>
                <cbc:CompanyID>{COMPANY_VAT_NUMBER}</cbc:CompanyID>
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:PartyTaxScheme>
            <cac:PartyLegalEntity>
                <cbc:RegistrationName>{COMPANY_NAME}</cbc:RegistrationName>
                <cbc:CompanyID>{COMPANY_VAT_NUMBER}</cbc:CompanyID>
            </cac:PartyLegalEntity>
           <cac:Contact>
            	<cbc:Name>{COMPANY_NAME}</cbc:Name>
              	<cbc:Telephone>{COMPANY_PHONE}</cbc:Telephone>
            	<cbc:ElectronicMail>{COMPANY_EMAIL}</cbc:ElectronicMail>
        	</cac:Contact>
        </cac:Party>
    </cac:AccountingSupplierParty>
    <cac:AccountingCustomerParty>
        <cac:Party>
            <cbc:EndpointID schemeID="0002">{CLIENT_ELECTRONIC_ADDRESS}</cbc:EndpointID>
            <cac:PartyIdentification>
                <cbc:ID schemeID="0002">{CLIENT_ID}</cbc:ID>
            </cac:PartyIdentification>
            <cac:PartyName>
                <cbc:Name>{CLIENT_NAME}</cbc:Name>
            </cac:PartyName>
            <cac:PostalAddress>
                <cbc:StreetName>{CLIENT_ADDRESS}</cbc:StreetName>
                <cbc:CityName>{CLIENT_CITY}</cbc:CityName>
                <cbc:PostalZone>{CLIENT_ZIP}</cbc:PostalZone>
                <cac:Country>
                    <cbc:IdentificationCode>{CLIENT_COUNTRY_CODE_ALPHA_2}</cbc:IdentificationCode>
                </cac:Country>
            </cac:PostalAddress>
            <cac:PartyTaxScheme>
                <cbc:CompanyID>{CLIENT_VAT_NUMBER}</cbc:CompanyID>
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:PartyTaxScheme>
            <cac:PartyLegalEntity>
                <cbc:RegistrationName>{CLIENT_NAME}</cbc:RegistrationName>
                <cbc:CompanyID schemeID="0183">{CLIENT_VAT_NUMBER}</cbc:CompanyID>
            </cac:PartyLegalEntity>
        </cac:Party>
    </cac:AccountingCustomerParty>
    <cac:PaymentMeans>
        <cbc:PaymentMeansCode>30</cbc:PaymentMeansCode>
        <cbc:PaymentID>{INVOICE_ID}</cbc:PaymentID>
        <cac:PayeeFinancialAccount>
            <cbc:ID>{COMPANY_IBAN}</cbc:ID>
            <cbc:Name>{COMPANY_NAME}</cbc:Name>
            <cac:FinancialInstitutionBranch>
                <cbc:ID>{COMPANY_SWIFT}</cbc:ID>
            </cac:FinancialInstitutionBranch>
        </cac:PayeeFinancialAccount>
  	</cac:PaymentMeans>
  
    {if $INVOICE_TAXABLE_ITEM_DISCOUNT}
      <cac:AllowanceCharge>
        <cbc:ChargeIndicator>false</cbc:ChargeIndicator>
        <cbc:AllowanceChargeReason>Discount on txable items</cbc:AllowanceChargeReason>
        <cbc:Amount currencyID="{CURRENCY_CODE}">{INVOICE_TAXABLE_ITEM_DISCOUNT}</cbc:Amount>
        <cac:TaxCategory>
          <cbc:ID>{TAX1_CATEGORY_ID}</cbc:ID>
          <cbc:Percent>{TAX1_PERCENT}</cbc:Percent>
          <cac:TaxScheme>
            <cbc:ID>VAT</cbc:ID>
          </cac:TaxScheme>
        </cac:TaxCategory>        
  	</cac:AllowanceCharge>{endif}
    
    {if $INVOICE_NON_TAXABLE_ITEM_DISCOUNT}
      <cac:AllowanceCharge>
        <cbc:ChargeIndicator>false</cbc:ChargeIndicator>
        <cbc:AllowanceChargeReason>Discount on non-taxable items</cbc:AllowanceChargeReason>
        <cbc:Amount currencyID="{CURRENCY_CODE}">{INVOICE_NON_TAXABLE_ITEM_DISCOUNT}</cbc:Amount>
        <cac:TaxCategory>
          <cbc:ID>Z</cbc:ID>
          <cbc:Percent>0</cbc:Percent>
          <cac:TaxScheme>
            <cbc:ID>VAT</cbc:ID>
          </cac:TaxScheme>
        </cac:TaxCategory>        
  	</cac:AllowanceCharge>{endif}
  
    <cac:TaxTotal>
        <cbc:TaxAmount currencyID="{CURRENCY_CODE}">{TAX_TOTAL_AMOUNT}</cbc:TaxAmount>
        {if $INVOICE_TAXABLE_SUBTOTAL}<cac:TaxSubtotal>
            <cbc:TaxableAmount currencyID="{CURRENCY_CODE}">{INVOICE_TAXABLE_SUBTOTAL}</cbc:TaxableAmount>
            <cbc:TaxAmount currencyID="{CURRENCY_CODE}">{TAX_TOTAL_AMOUNT}</cbc:TaxAmount>
            <cac:TaxCategory>
                <cbc:ID>{TAX1_CATEGORY_ID}</cbc:ID>
                <cbc:Percent>{TAX1_PERCENT}</cbc:Percent>
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:TaxCategory>
        </cac:TaxSubtotal>{endif}
      
        {if $INVOICE_NON_TAXABLE_SUBTOTAL}<cac:TaxSubtotal>
              <cbc:TaxableAmount currencyID="{CURRENCY_CODE}">{INVOICE_NON_TAXABLE_SUBTOTAL}</cbc:TaxableAmount>
              <cbc:TaxAmount currencyID="{CURRENCY_CODE}">0</cbc:TaxAmount>
              <cac:TaxCategory>
                  <cbc:ID>Z</cbc:ID>
                  <cbc:Percent>0</cbc:Percent>
                  <cac:TaxScheme>
                      <cbc:ID>VAT</cbc:ID>
                  </cac:TaxScheme>
              </cac:TaxCategory>
          </cac:TaxSubtotal>{endif}
    </cac:TaxTotal>
    <cac:LegalMonetaryTotal>
        <cbc:LineExtensionAmount currencyID="{CURRENCY_CODE}">{INVOICE_SUBTOTAL}</cbc:LineExtensionAmount>
        <cbc:TaxExclusiveAmount currencyID="{CURRENCY_CODE}">{INVOICE_TOTAL_BEFORE_TAX}</cbc:TaxExclusiveAmount>
        <cbc:TaxInclusiveAmount currencyID="{CURRENCY_CODE}">{INVOICE_TOTAL}</cbc:TaxInclusiveAmount>
        <cbc:AllowanceTotalAmount currencyID="{CURRENCY_CODE}">{INVOICE_DISCOUNT_TOTAL}</cbc:AllowanceTotalAmount>
        <cbc:ChargeTotalAmount currencyID="{CURRENCY_CODE}">0</cbc:ChargeTotalAmount>
        <cbc:PayableAmount currencyID="{CURRENCY_CODE}">{INVOICE_TOTAL}</cbc:PayableAmount>
    </cac:LegalMonetaryTotal>
    {INVOICE_LINES}<cac:InvoiceLine>
        <cbc:ID>{INVOICE_LINE_ITEM_ID}</cbc:ID>
        <cbc:InvoicedQuantity unitCode="C62">{INVOICE_LINE_QUANTITY}</cbc:InvoicedQuantity>
        <cbc:LineExtensionAmount currencyID="{CURRENCY_CODE}">{INVOICE_LINE_TOTAL}</cbc:LineExtensionAmount>
        <cac:OrderLineReference>
            <cbc:LineID>{INVOICE_LINE_SERIAL}</cbc:LineID>
        </cac:OrderLineReference>
        <cac:Item>
            <cbc:Description>{INVOICE_LINE_DESCRIPTION}</cbc:Description>
            <cbc:Name>{INVOICE_LINE_TITLE}</cbc:Name>
            <cac:OriginCountry>
                <cbc:IdentificationCode>{COMPANY_COUNTRY_CODE}</cbc:IdentificationCode>
            </cac:OriginCountry>
            <cac:ClassifiedTaxCategory>
                <cbc:ID>{INVOICE_LINE_TAX1_CATEGORY_ID}</cbc:ID>
                <cbc:Percent>{INVOICE_LINE_TAX1_PERCENT}</cbc:Percent>
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:ClassifiedTaxCategory>
        </cac:Item>
        <cac:Price>
            <cbc:PriceAmount currencyID="{CURRENCY_CODE}">{INVOICE_LINE_RATE}</cbc:PriceAmount>
        </cac:Price>
    </cac:InvoiceLine>{/INVOICE_LINES}
</Invoice>