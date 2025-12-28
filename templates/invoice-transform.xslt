<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:ubl="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
    xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
    xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
    exclude-result-prefixes="ubl cac cbc">

    <xsl:output method="html" indent="yes"/>

    <xsl:template match="/ubl:Invoice">
        <html>
            <head>
                <title>Invoice <xsl:value-of select="cbc:ID"/></title>
                <style>
                    body { font-family: Arial, sans-serif; margin: 40px; color: #333; }
                    .header { display: flex; justify-content: space-between; margin-bottom: 40px; border-bottom: 2px solid #eee; padding-bottom: 20px; }
                    .details { display: flex; justify-content: space-between; margin-bottom: 30px; }
                    .box { width: 45%; }
                    h1 { color: #2c3e50; }
                    h3 { border-bottom: 1px solid #ccc; padding-bottom: 5px; margin-bottom: 10px; font-size: 1.1em; }
                    table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                    th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
                    th { background-color: #f8f9fa; font-weight: bold; }
                    .totals { margin-top: 30px; text-align: right; }
                    .totals p { margin: 5px 0; font-size: 1.1em; }
                    .grand-total { font-weight: bold; font-size: 1.3em; color: #2c3e50; }
                </style>
            </head>
            <body>
                <div class="header">
                    <div>
                        <xsl:choose>
                            <xsl:when test="cbc:InvoiceTypeCode = '381'">
                                <h1>CREDIT NOTE</h1>
                            </xsl:when>
                            <xsl:otherwise><h1>INVOICE</h1></xsl:otherwise>
                        </xsl:choose>
                    </div>
                    <div style="text-align: right;">
                        <p><strong>Invoice #:</strong> <xsl:value-of select="cbc:ID"/></p>
                        <p><strong>Date:</strong> <xsl:value-of select="cbc:IssueDate"/></p>
                        <p><strong>Due Date:</strong> <xsl:value-of select="cbc:DueDate"/></p>
                    </div>
                </div>

                <div class="details">
                    <div class="box">
                        <h3>Supplier</h3>
                        <p><strong><xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PartyName/cbc:Name"/></strong></p>
                        <p><xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PostalAddress/cbc:StreetName"/></p>
                        <p><xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PostalAddress/cbc:CityName"/>, <xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PostalAddress/cbc:PostalZone"/></p>
                        <p><xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PostalAddress/cac:Country/cbc:IdentificationCode"/></p>
                    </div>
                    <div class="box">
                        <h3>Bill To</h3>
                        <p><strong><xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PartyName/cbc:Name"/></strong></p>
                        <p><xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PostalAddress/cbc:StreetName"/></p>
                        <p><xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PostalAddress/cbc:CityName"/>, <xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PostalAddress/cbc:PostalZone"/></p>
                        <p><xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PostalAddress/cac:Country/cbc:IdentificationCode"/></p>
                    </div>
                </div>

                <table>
                    <thead>
                        <tr>
                            <th>Description</th>
                            <th style="text-align: center;">Qty</th>
                            <th style="text-align: right;">Unit Price</th>
                            <th style="text-align: right;">Total</th>
                        </tr>
                    </thead>
                    <tbody>
                        <xsl:for-each select="cac:InvoiceLine">
                            <tr>
                                <td><xsl:value-of select="cac:Item/cbc:Name"/></td>
                                <td style="text-align: center;"><xsl:value-of select="cbc:InvoicedQuantity"/></td>
                                <td style="text-align: right;"><xsl:value-of select="cac:Price/cbc:PriceAmount"/> <xsl:value-of select="cac:Price/cbc:PriceAmount/@currencyID"/></td>
                                <td style="text-align: right;"><xsl:value-of select="cbc:LineExtensionAmount"/> <xsl:value-of select="cbc:LineExtensionAmount/@currencyID"/></td>
                            </tr>
                        </xsl:for-each>
                    </tbody>
                </table>

                <div class="totals">
                    <p>Subtotal: <xsl:value-of select="cac:LegalMonetaryTotal/cbc:TaxExclusiveAmount"/> <xsl:value-of select="cac:LegalMonetaryTotal/cbc:TaxExclusiveAmount/@currencyID"/></p>
                    <p>Tax: <xsl:value-of select="cac:TaxTotal/cbc:TaxAmount"/> <xsl:value-of select="cac:TaxTotal/cbc:TaxAmount/@currencyID"/></p>
                    <p class="grand-total">Total: <xsl:value-of select="cac:LegalMonetaryTotal/cbc:TaxInclusiveAmount"/> <xsl:value-of select="cac:LegalMonetaryTotal/cbc:TaxInclusiveAmount/@currencyID"/></p>
                </div>
            </body>
        </html>
    </xsl:template>
</xsl:stylesheet>