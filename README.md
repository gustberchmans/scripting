# Automatisering van Peppol-factuurverwerking met MySQL, Docker en PowerShell

## 1. Introductie
Voor mijn werkstuk wil ik een systeem bouwen dat Peppol-XML-facturen automatisch verwerkt.
Het idee is om een workflow te maken waarin:
- MySQL nieuwe factuurrecords herkent,
- een Docker-container met PowerShell de gegevens verwerkt,
- en er uiteindelijk een PDF wordt gemaakt volgens een vaste template.

Deze aanpak combineert databanken, automatisering, scripting en best practices.
In dit voorstel leg ik uit wat ik wil bouwen en hoe mijn project zal voldoen aan alle beoordelingscriteria.

## 2. Analyse
### 2.1 Situatieschets
Peppol-facturen worden normaal als XML geleverd. Zonder automatisatie moeten deze manueel omgezet of gecontroleerd worden.
Dat is traag, foutgevoelig en moeilijk op te schalen.
Mijn project richt zich daarom op het analyseren van deze huidige manier van werken en het identificeren van punten die ik wil verbeteren.

### 2.2 SWOT-analyse
**Sterktes**
- Ik heb al ervaring met MySQL en Docker, waardoor ik vlot kan starten.
- Peppol gebruikt gestandaardiseerde XML, wat helpt bij de verwerking.
- De workflow kan bijna volledig geautomatiseerd worden.

**Zwaktes**
- De combinatie MySQL + Docker + PowerShell maakt de omgeving complexer.
- Het systeem hangt af van de beschikbaarheid van de Docker-container.

**Kansen**
- Door strengere Europese regels rond e-facturatie is dit een actueel en nuttig project.
- Het ontwerp biedt mogelijkheden om later functies toe te voegen, zoals rapportage of een webinterface.

**Bedreigingen**
- Onjuiste verwerking kan leiden tot compliance-problemen.
- Beveiliging moet zorgvuldig uitgewerkt worden om datalekken te vermijden.

Deze analyse toont waarom een gecontroleerde en betrouwbare automatisering nodig is.

## 3. Design
### 3.1 Doel van het ontwerp
Tijdens de ontwerpfase wil ik verschillende technologieën vergelijken en motiveren waarom ik een bepaalde oplossing kies.

### 3.2 Mogelijke onderdelen van de oplossing
Ik zal onderzoeken of de volgende elementen geschikt zijn:
- MySQL-triggers die automatisch reageren op nieuwe factuurobjecten
- Een Docker-container waarin PowerShell draait
- PowerShell-scripts voor parsing, validatie en PDF-generatie
- XSLT-transformatie om XML naar HTML om te zetten
- iTextSharp om HTML naar een PDF te converteren

### 3.3 Creativiteit
Het systeem dat ik voorstel moet:
- automatisch reageren op nieuwe databank-events,
- gebruikmaken van herbruikbare templates,
- en ontworpen zijn zodat uitbreidingen later eenvoudig blijven.

### 3.4 Minimum Viable Product (MVP)
De MVP definieert de minimale set van functies die absoluut noodzakelijk zijn om aan te tonen dat de kern van de voorgestelde oplossing werkt en het oorspronkelijke probleem oplost. Dit is de scope waar ik me in eerste instantie op zal focussen om de haalbaarheid van het project te garanderen.

De MVP omvat de volgende functionaliteiten:
- **Factuurherkenning:** Een MySQL-tabelstructuur die in staat is om de essentiële factuurdata van één gespecificeerd Peppol-factuurtype op te slaan (bijv. UBL-CIUS-NL).
- **Trigger en Event-Handling:** Een werkende MySQL-trigger die een event of record aanmaakt of markeert zodra een nieuw factuurrecord is ingevoegd.
- **Gegevensverwerking:** Een Docker-container met een werkend PowerShell-script dat periodiek (of op basis van het event) factuurdata uit de MySQL-database leest.
- **Transformatie:** Het PowerShell-script voert XSLT-transformatie uit op een gesimuleerde XML-input of de data uit de database om deze om te zetten naar een eenvoudig HTML-formaat.
- **Documentgeneratie:** Het systeem gebruikt een module (zoals iTextSharp) om de gegenereerde HTML om te zetten naar een statische PDF op basis van een eenvoudige, vaste template.
- **Logging en Foutafhandeling:** Basis logging van een geslaagde verwerking en de afhandeling van één kritieke fout (bijv. factuurdata ontbreekt).

Dit MVP-systeem toont de volledige geautomatiseerde keten: Database (Trigger) → PowerShell/Docker (Verwerking) → PDF (Output).

### 3.5 Toekomstige Uitbreidingen (Future Scope)
Na succesvolle implementatie en validatie van de MVP, kunnen de volgende functies als mogelijke extra's worden toegevoegd. Deze zullen in volgorde van relevantie worden aangepakt, indien de beschikbare tijd dit toelaat.
- **Uitgebreide Foutafhandeling:** Implementatie van een robuustere foutafhandeling, inclusief het tijdelijk opslaan van niet-verwerkte facturen (Error-queue of Retry-tabel) en de mogelijkheid tot e-mailnotificaties bij kritieke fouten (zoals vermeld in sectie 5 en 6).
- **Ondersteuning voor Meerdere Factuurtypes:** Het uitbreiden van de logica om meerdere Peppol-standaarden of XML-schema's te valideren en verwerken.
- **Geavanceerde Validatie:** Implementatie van diepgaande datavalidatie (bijv. controleren of totaalbedrag = som van regels) om de robuustheid (sectie 6) te verhogen.
- **Integratie met Cloud-Platformen:** Onderzoek naar het uploaden van de gegenereerde PDF naar een externe service (bijv. OneDrive, SharePoint of een ERP-systeem) om de workflow te finaliseren.
- **Visuele Interface/Rapportage:** Het toevoegen van een eenvoudige webinterface of een Powershell rapportagemodule om de status van de verwerkte en in de wachtrij staande facturen te visualiseren (zoals vermeld in de Kansen in de SWOT-analyse).

## 4. Kennisverwerving
In dit onderdeel beschrijf ik hoe ik de nodige kennis zal opbouwen.
Dat omvat:
- PowerShell scripting en modules
- De werking van Docker-containers
- XML-analyse en XSLT-transformatie
- MySQL triggers en event handling
- Basisprincipes van security, zoals token-verificatie

Ik geef aan welke documentatie, tutorials of bronnen ik hiervoor wil raadplegen.

## 5. Usability
Hoewel het project vooral backend-gericht is, wil ik het systeem toch gebruiksvriendelijk maken.
Ik plan:
- duidelijke logberichten,
- heldere foutmeldingen,
- overzichtelijke documentatie,
- en eventueel e-mailmeldingen wanneer een verwerking geslaagd is of fouten bevat.

Zo kan iemand anders het systeem ook eenvoudig gebruiken of onderhouden.

## 6. Robustheid
Het ontwerp besteedt veel aandacht aan stabiliteit en foutverwerking.
Daarom voorzie ik:
- Validatie van de XML-data
- Uitgebreide foutafhandeling in PowerShell
- Logging van alle belangrijke stappen
- Mogelijkheid om facturen tijdelijk op te slaan wanneer de container offline is
- Controles op geldigheid van de inkomende gegevens

Zo wordt het uiteindelijke systeem betrouwbaar, ook wanneer er problemen zijn met input of omgeving.

## 7. Uitbreidbaarheid
Het systeem wordt modulair opgebouwd zodat er later eenvoudig nieuwe onderdelen toegevoegd kunnen worden.
Mogelijke uitbreidingen zijn:
- Nieuwe factuurtypes
- Extra uitvoerformaten
- Integratie met cloud-platformen
- Een visuele interface
- Nieuwe validatieregels

Door dit vooraf mee te nemen in het ontwerp blijft de structuur overzichtelijk en toekomstgericht.

## 8. Best Practices en Structuur
Ik plan het project op te bouwen volgens bekende best practices:
- PowerShell-conventies zoals Verb-Noun functienamen
- Duidelijke mappenstructuur en scheiding van code, configuratie en logs
- Gebruik van configuratiebestanden om instellingen flexibel te houden
- Efficiënte Docker-opbouw zodat de container klein en snel blijft

Dit bevordert leesbaarheid, onderhoudbaarheid en prestaties.

## 9. Testing (Pester)
Ik zal Pester gebruiken om unittests te schrijven zodra het systeem gebouwd wordt.
In het voorstel beschrijf ik welke tests ik wil voorzien, onder andere:
- Validatie van XML-input
- Testen van XSLT-transformatie
- Testen of PDF-generatie correct verloopt
- Foutafhandeling
- Token-verificatie
- Simulaties van MySQL-triggers

Deze testaanpak zorgt ervoor dat het project later makkelijker uitbreidbaar en beter controleerbaar wordt.

---

## Sources:
- Gemini
- https://risedocs.fairsketch.com/doc/view/164-peppol-ubl-invoice-2-1-bis-billing-3-0-e-invoice-template

## Cmd's to run
"""
    docker-compose down -v && docker-compose up --build
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

