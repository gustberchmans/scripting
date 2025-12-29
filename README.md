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

## 2. Architectuur
Het systeem bestaat uit drie hoofdcomponenten die samenwerken in een Docker-omgeving:

1.  **MySQL Database:**
    *   Slaat factuurdata op in de tabel `invoices`.
    *   Gebruikt triggers voor audit logging in `invoice_audit`.
2.  **PowerShell Container (App):**
    *   Draait het entry-script `Process-Invoices.ps1`.
    *   Alle logica (loop, validatie, verwerking) bevindt zich in de module `PeppolProcessor`.
3.  **Output Volume:**
    *   Gegenereerde PDF's worden opgeslagen in de gedeelde map `output/`.

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

```
See the failed invoices:
```
    docker-compose exec app pwsh /app/src/Get-Report.ps1
```

## Sources:
- Gemini Code Assist: Chat
- https://risedocs.fairsketch.com/doc/view/164-peppol-ubl-invoice-2-1-bis-billing-3-0-e-invoice-template
