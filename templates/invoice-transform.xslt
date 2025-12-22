<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:inv="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
                xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
                xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
                exclude-result-prefixes="inv cac cbc">

  <xsl:output method="html" indent="yes" encoding="UTF-8"/>

  <xsl:template match="/inv:Invoice">
    <html>
      <head>
        <title>Factuur <xsl:value-of select="cbc:ID"/>
        </title>
        <style>
          body { font-family: sans-serif; }
          .container { max-width: 800px; margin: auto; padding: 20px; border: 1px solid #eee; }
          h1, h2 { color: #333; }
          table { width: 100%; border-collapse: collapse; margin-top: 20px; }
          th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
          th { background-color: #f2f2f2; }
          .totals { float: right; width: 300px; margin-top: 20px; }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>Factuur #<xsl:value-of select="cbc:ID"/></h1>
          <p>
            <strong>Datum:</strong>
            <xsl:value-of select="cbc:IssueDate"/><br/>
            <strong>Vervaldatum:</strong>
            <xsl:value-of select="cbc:DueDate"/>
          </p>

          <h2>Leverancier</h2>
          <p>
            <xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PartyName/cbc:Name"/><br/>
            <xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PostalAddress/cbc:StreetName"/><br/>
            <xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PostalAddress/cbc:PostalZone"/>
            <xsl:text> </xsl:text>
            <xsl:value-of select="cac:AccountingSupplierParty/cac:Party/cac:PostalAddress/cbc:CityName"/>
          </p>

          <h2>Klant</h2>
          <p>
            <xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PartyName/cbc:Name"/><br/>
            <xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PostalAddress/cbc:StreetName"/><br/>
            <xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PostalAddress/cbc:PostalZone"/>
            <xsl:text> </xsl:text>
            <xsl:value-of select="cac:AccountingCustomerParty/cac:Party/cac:PostalAddress/cbc:CityName"/>
          </p>

          <h2>Factuurregels</h2>
          <table>
            <tr>
              <th>Omschrijving</th>
              <th>Aantal</th>
              <th>Prijs per stuk</th>
              <th>Totaal</th>
            </tr>
            <xsl:for-each select="cac:InvoiceLine">
              <tr>
                <td><xsl:value-of select="cac:Item/cbc:Name"/></td>
                <td><xsl:value-of select="cbc:InvoicedQuantity"/></td>
                <td><xsl:value-of select="format-number(cac:Price/cbc:PriceAmount, '#,##0.00')"/></td>
                <td><xsl:value-of select="format-number(cbc:LineExtensionAmount, '#,##0.00')"/></td>
              </tr>
            </xsl:for-each>
          </table>

          <div class="totals">
            <h2>Totaal</h2>
            <p>
              <strong>Totaal excl. BTW:</strong>
              <xsl:value-of select="format-number(cac:LegalMonetaryTotal/cbc:TaxExclusiveAmount, '#,##0.00')"/>
              <br/>
              <strong>Totaal incl. BTW:</strong>
              <xsl:value-of select="format-number(cac:LegalMonetaryTotal/cbc:TaxInclusiveAmount, '#,##0.00')"/>
              <br/>
              <strong>Te betalen:</strong>
              <xsl:value-of select="format-number(cac:LegalMonetaryTotal/cbc:PayableAmount, '#,##0.00')"/>
            </p>
          </div>
        </div>
      </body>
    </html>
  </xsl:template>

</xsl:stylesheet>
