# Automatisering van Peppol-factuurverwerking met MySQL, Docker en PowerShell

## 1. Introductie & Handleiding
Dit project is een volledig geautomatiseerd systeem voor het verwerken van Peppol-XML-facturen. Het systeem monitort een MySQL-database op nieuwe facturen, valideert de gegevens volgens strikte bedrijfsregels, en genereert automatisch een PDF-document op basis van een XSLT-template.

### Functionaliteiten
*   **Factuurherkenning:** Automatische detectie van nieuwe records in de database.
*   **Validatie:** Controle op totalen, BTW-berekeningen en bedrijfsregels (bv. geen negatieve prijzen).
*   **Transformatie:** Omzetting van UBL XML naar HTML via XSLT.
*   **PDF Generatie:** Conversie van HTML naar PDF met behulp van iText 7.
*   **Rapportage:** Ingebouwde module voor statusrapporten (HTML).
*   **Cloud Integratie:** Simulatie van upload naar externe opslag.

## 2. Architectuur & Ontwerpkeuzes

### Systeemarchitectuur
Het systeem bestaat uit drie hoofdcomponenten die samenwerken in een container-omgeving via Docker Compose:

1.  **MySQL Database**:
    *   Slaat de rauwe Peppol XML-facturen en de daaruit geëxtraheerde metadata (zoals leveranciers- en klanten-BTW-nummers, status en verwerkingstijdstippen) op in de tabel `invoices`.
    *   Voorziet automatische audit logging via een database trigger naar de tabel `invoice_audit` bij het binnenkomen van nieuwe facturen.
2.  **PowerShell Core Container (App)**:
    *   Draait de verwerkingsloop binnen een containerized PowerShell 7 runtime.
    *   De core-logica is volledig geïsoleerd en modulair opgebouwd in de scriptmodule [PeppolProcessor](file:///home/gustb/Documents/02. School/02. Scripting/v1/src/PeppolProcessor.psm1).
3.  **Output Volume**:
    *   Een gedeelde map (`output/`) op het hostsysteem waarin de gegenereerde PDF-documenten en statusrapporten terechtkomen.

---

### Ontwerppatroon: Bootstrapper & Scriptmodule
In plaats van alle logica rechtstreeks in één uitvoerbaar script te plaatsen, gebruikt dit project het **Bootstrapper-ontwerppatroon**:
*   **De Module ([PeppolProcessor.psm1](file:///home/gustb/Documents/02. School/02. Scripting/v1/src/PeppolProcessor.psm1))**: Bevat alle herbruikbare functies (databaseverbinding, XML-validatie, transformatie en PDF-generatie). Dit scheidt de logica volledig van de runtime-omgeving en maakt het mogelijk om individuele functies eenvoudig unit te testen (bijvoorbeeld met Pester) zonder dat de verwerkingsloop gestart hoeft te worden.
*   **De Bootstrapper ([Process-Invoices.ps1](file:///home/gustb/Documents/02. School/02. Scripting/v1/src/Process-Invoices.ps1))**: Een dunne schil (entrypoint script) die de runtime-omgeving configureert, de module inlaadt en de hoofdloop `Start-PeppolProcessor` start. Dit patroon volgt PowerShell best practices voor herbruikbaarheid en enterprise-architecturen.

---

### Technologie-evaluatie & Alternatieven

#### Waarom PowerShell Core & MySQL?
*   **PowerShell Core**: Biedt naadloze cross-platform functionaliteit (draait in Linux Docker containers), heeft ingebouwde XML-parsering via .NET's `[xml]` typeversneller, en kan direct .NET-bibliotheken (DLL's) inladen voor PDF-generatie.
*   **MySQL**: Een betrouwbare, ACID-compliante relationele database die uitstekende ondersteuning biedt voor triggers, transacties en metadata-opslag.

#### Waarom iText 7 (iTextSharp) voor PDF-generatie?
Voor de conversie van UBL XML naar PDF wordt de XML eerst via een XSLT-template getransformeerd naar HTML, waarna **iText 7** (met de `html2pdf` add-on) de HTML omzet naar een A4 PDF-document.

**Alternatieven en waarom ze werden verworpen:**
1.  **wkhtmltopdf**:
    *   *Werking*: Converteert HTML naar PDF met behulp van de WebKit-rendering engine.
    *   *Nadeel*: Het project is momenteel "deprecated" en wordt niet langer actief onderhouden. Het heeft bekende beveiligingslekken en vereist het installeren van een externe binaire dependency buiten de .NET-omgeving.
2.  **Puppeteer / Playwright (Headless Chrome)**:
    *   *Werking*: Converteert HTML via een headless browser.
    *   *Nadeel*: Zeer zwaar. Vereist Node.js en het downloaden van een complete Chromium-binaire binnen de container, wat de Docker-image aanzienlijk vergroot en onnodig veel resources verbruikt.
3.  **Apache FOP (Formatting Objects Processor)**:
    *   *Werking*: Converteert XML rechtstreeks naar PDF met XSL-FO (Extensible Stylesheet Language Formatting Objects).
    *   *Nadeel*: Vereist een Java-runtime, heeft een zeer steile leercurve en het schrijven van XSL-FO stylesheets is complexer en trager dan het stylen van een HTML-document met CSS.
4.  **PDFsharp / QuestPDF**:
    *   *Werking*: Directe .NET-libraries om PDF's op te bouwen via code.
    *   *Nadeel*: PDFsharp heeft zeer beperkte en verouderde ondersteuning voor HTML-conversie. QuestPDF is uitstekend voor lay-out via code (fluent API), maar ondersteunt geen directe conversie van HTML-templates uit XSLT, waardoor elke lay-out handmatig geprogrammeerd zou moeten worden.

**Besluit**: **iText 7** biedt de perfecte balans. Het is een native .NET-bibliotheek die direct in PowerShell geladen kan worden, moderne HTML5/CSS3 conversie ondersteunt via `html2pdf`, platformonafhankelijk is, en een minimale voetafdruk heeft binnen de Docker-container.

## 3. Installatie & Gebruik (Getting Started)

### Vereisten
*   Docker & Docker Compose
*   PowerShell Core (optioneel, voor lokale helper scripts)

### Configuratie
De applicatie wordt geconfigureerd via Environment Variables in `docker-compose.yml`.
*   `DB_HOST`: De hostnaam van de database container (standaard: `db`).
*   `DB_USER`: Database gebruiker (standaard: `root`).
*   `DB_PASSWORD`: Database wachtwoord.
*   `DB_DATABASE`: Naam van de database (standaard: `invoices_db`).
*   `API_TOKEN`: (Optioneel) Token voor toekomstige API authenticatie.

### Starten
1.  Bouw en start de containers:
    ```bash
    docker-compose up --build
    ```
2.  Het systeem wacht automatisch tot de database beschikbaar is en begint dan met pollen.

### Testdata Invoeren
Gebruik het helper script om voorbeeld-facturen (zowel valide als invalide) in de database te laden:
```bash
pwsh ./src/Insert-Data.ps1
```

### Resultaten Bekijken
*   **PDF's:** Controleer de map `output/` op uw host machine.
*   **Rapportage:** Genereer een statusrapport met het volgende commando:
    ```bash
    docker-compose exec app pwsh /app/src/Get-Report.ps1
    ```
    Open vervolgens `output/status_report.html` in uw browser.

## 4. Ontwikkeling & Testing

### Structuur
*   `src/PeppolProcessor.psm1`: De centrale module met alle logica (Main loop, Validatie, DB, PDF, Import).
*   `src/Process-Invoices.ps1`: Entry point script dat de `Start-PeppolProcessor` functie aanroept.
*   `src/Insert-SampleData.ps1`: Wrapper script om testdata in te laden via de module.
*   `src/Get-Report.ps1`: Script voor het genereren van statusrapporten.
*   `templates/`: Bevat de XSLT transformatie regels.

### Tests Draaien
Het project bevat uitgebreide Pester tests voor validatie en logica.
```bash
docker-compose exec app pwsh -c "Invoke-Pester /app/tests/Process-Invoices.Tests.ps1 -Output Detailed"
```

---

## Handmatige SQL Commando's (Optioneel)
Indien u handmatig data wilt inspecteren of invoegen:

**Verbinden met de database:**
```
    docker-compose down -v && docker-compose up --build
```
Else:
```
    docker-compose up --build
```
Run tests:
```
docker-compose exec app pwsh -c "Invoke-Pester /app/tests/Process-Invoices.Tests.ps1 -Output Detailed"
```
Add new invoice in database:
```
    docker exec -it v1-db-1 mysql -u root -p invoices_db
```
```
    INSERT INTO invoices (peppol_xml, status) VALUES (
'<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
    <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID>
    <cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID>
    <cbc:ID>INV-MANUAL-001</cbc:ID>
    <cbc:IssueDate>2023-12-23</cbc:IssueDate>
    <cbc:DueDate>2024-01-23</cbc:DueDate>
    <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
    <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
    <cbc:BuyerReference>REF-MANUAL</cbc:BuyerReference>
    <cac:AccountingSupplierParty>
        <cac:Party>
            <cac:PartyName><cbc:Name>Manual Supplier Inc.</cbc:Name></cac:PartyName>
            <cac:PostalAddress><cac:Country><cbc:IdentificationCode>NL</cbc:IdentificationCode></cac:Country></cac:PostalAddress>
            <cac:PartyLegalEntity><cbc:RegistrationName>Manual Supplier Inc.</cbc:RegistrationName></cac:PartyLegalEntity>
        </cac:Party>
    </cac:AccountingSupplierParty>
    <cac:AccountingCustomerParty>
        <cac:Party>
            <cac:PartyName><cbc:Name>Manual Customer Ltd.</cbc:Name></cac:PartyName>
            <cac:PostalAddress><cac:Country><cbc:IdentificationCode>NL</cbc:IdentificationCode></cac:Country></cac:PostalAddress>
            <cac:PartyLegalEntity><cbc:RegistrationName>Manual Customer Ltd.</cbc:RegistrationName></cac:PartyLegalEntity>
        </cac:Party>
    </cac:AccountingCustomerParty>
    <cac:TaxTotal>
        <cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount>
        <cac:TaxSubtotal>
            <cbc:TaxableAmount currencyID="EUR">100.00</cbc:TaxableAmount>
            <cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount>
            <cac:TaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>21</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:TaxCategory>
        </cac:TaxSubtotal>
    </cac:TaxTotal>
    <cac:LegalMonetaryTotal>
        <cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount>
        <cbc:TaxExclusiveAmount currencyID="EUR">100.00</cbc:TaxExclusiveAmount>
        <cbc:TaxInclusiveAmount currencyID="EUR">121.00</cbc:TaxInclusiveAmount>
        <cbc:PayableAmount currencyID="EUR">121.00</cbc:PayableAmount>
    </cac:LegalMonetaryTotal>
    <cac:InvoiceLine>
        <cbc:ID>1</cbc:ID>
        <cbc:InvoicedQuantity unitCode="C62">1</cbc:InvoicedQuantity>
        <cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount>
        <cac:Item><cbc:Name>Manual Test Item</cbc:Name></cac:Item>
        <cac:Price><cbc:PriceAmount currencyID="EUR">100.00</cbc:PriceAmount></cac:Price>
    </cac:InvoiceLine>
</Invoice>', 
'new');

```
```
    INSERT INTO invoices (peppol_xml, status) VALUES (
'<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
    <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID>
    <cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID>
    <cbc:ID>INV-MANUAL-001</cbc:ID>
    <cbc:IssueDate>2023-12-23</cbc:IssueDate>
    <cbc:DueDate>2024-01-23</cbc:DueDate>
    <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
    <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
    <cbc:BuyerReference>REF-MANUAL</cbc:BuyerReference>
    <cac:AccountingSupplierParty>
        <cac:Party>
            <cac:PartyName><cbc:Name>Manual Supplier Inc.</cbc:Name></cac:PartyName>
            <cac:PostalAddress><cac:Country><cbc:IdentificationCode>NL</cbc:IdentificationCode></cac:Country></cac:PostalAddress>
            <cac:PartyLegalEntity><cbc:RegistrationName>Manual Supplier Inc.</cbc:RegistrationName></cac:PartyLegalEntity>
        </cac:Party>
    </cac:AccountingSupplierParty>
    <cac:AccountingCustomerParty>
        <cac:Party>
            <cac:PartyName><cbc:Name>Manual Customer Ltd.</cbc:Name></cac:PartyName>
            <cac:PostalAddress><cac:Country><cbc:IdentificationCode>NL</cbc:IdentificationCode></cac:Country></cac:PostalAddress>
            <cac:PartyLegalEntity><cbc:RegistrationName>Manual Customer Ltd.</cbc:RegistrationName></cac:PartyLegalEntity>
        </cac:Party>
    </cac:AccountingCustomerParty>
    <cac:TaxTotal>
        <cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount>
        <cac:TaxSubtotal>
            <cbc:TaxableAmount currencyID="EUR">200.00</cbc:TaxableAmount>
            <cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount>
            <cac:TaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>21</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:TaxCategory>
        </cac:TaxSubtotal>
    </cac:TaxTotal>
    <cac:LegalMonetaryTotal>
        <cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount>
        <cbc:TaxExclusiveAmount currencyID="EUR">100.00</cbc:TaxExclusiveAmount>
        <cbc:TaxInclusiveAmount currencyID="EUR">121.00</cbc:TaxInclusiveAmount>
        <cbc:PayableAmount currencyID="EUR">121.00</cbc:PayableAmount>
    </cac:LegalMonetaryTotal>
    <cac:InvoiceLine>
        <cbc:ID>1</cbc:ID>
        <cbc:InvoicedQuantity unitCode="C62">1</cbc:InvoicedQuantity>
        <cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount>
        <cac:Item><cbc:Name>Manual Test Item</cbc:Name></cac:Item>
        <cac:Price><cbc:PriceAmount currencyID="EUR">100.00</cbc:PriceAmount></cac:Price>
    </cac:InvoiceLine>
</Invoice>', 
'new');
See the failed invoices:
```
    docker-compose exec app pwsh /app/src/Get-Report.ps1
```

## 5. Designbeslissingen & Bronvermelding

Voor een gedetailleerde toelichting op de gekozen technologieën (zoals Docker, MySQL, PowerShell Core en iText 7), de overwogen alternatieven (wkhtmltopdf, Puppeteer, QuestPDF) en de motivatie achter de script/module-architectuur, wordt verwezen naar het document [DESIGN.md](file:///home/gustb/Documents/02.%20School/02.%20Scripting/v1/DESIGN.md).

### Bronvermelding & Referenties

1.  **Peppol BIS Billing 3.0 Standard:** Officiële specificatie van de Europese norm voor e-facturatie (EN 16931). [Peppol BIS Billing 3.0 Documentation](https://peppol.eu/what-is-peppol/peppol-profiles/).
2.  **OASIS Universal Business Language (UBL) 2.1:** XML-schema standaard voor zakelijke documenten. [OASIS UBL 2.1 Standard](http://docs.oasis-open.org/ubl/os-UBL-2.1/UBL-2.1.html).
3.  **iText 7 for .NET (html2pdf):** API-documentatie voor HTML-naar-PDF conversie. [iText 7 Developer Guide](https://itextpdf.com/en/resources/books/itext-7-converting-html-pdf-pdfhtml).
4.  **SimplySql PowerShell Module:** Object-georiënteerde SQL client voor PowerShell. [SimplySql GitHub Repository](https://github.com/rcbensley/SimplySql).
5.  **Pester 5 Testing Framework:** Documentatie voor het PowerShell unit testing framework. [Pester Docs](https://pester.dev/docs/quick-start).
6.  **UBL-CIUS-NL Billing 3.0 Template:** Template voor Nederlandse Peppol-facturen. [RiseDocs NL CIUS Template](https://risedocs.fairsketch.com/doc/view/164-peppol-ubl-invoice-2-1-bis-billing-3-0-e-invoice-template).
