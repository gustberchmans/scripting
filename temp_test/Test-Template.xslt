<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" indent="yes" encoding="UTF-8"/>
  <xsl:template match="/Invoice">
    <html>
      <head>
        <title>Factuur</title>
        <style>
          body { font-family: sans-serif; padding: 20px; }
          .container { max-width: 800px; margin: auto; padding: 20px; border: 1px solid #ddd; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
          h1 { color: #333; border-bottom: 2px solid #f2f2f2; padding-bottom: 10px; }
          p { font-size: 1.1em; }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>Factuur</h1>
          <p><strong>Factuurnummer: </strong> <xsl:value-of select="InvoiceID"/></p>
          <p><strong>Klant: </strong> <xsl:value-of select="Customer"/></p>
          <p><strong>Omschrijving: </strong> <xsl:value-of select="Item"/></p>
          <p><strong>Bedrag: </strong> €<xsl:value-of select="format-number(Amount, '#,##0.00')"/></p>
        </div>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
