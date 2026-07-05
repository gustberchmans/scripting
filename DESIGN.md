# Design- en Technologiekeuzes — Peppol Factuurverwerking

Dit document beschrijft de architectuur, de technologiekeuzes en de alternatieven die zijn overwogen voor het project **Automatisering van Peppol-factuurverwerking met MySQL, Docker en PowerShell**. Het dient tevens als formele verantwoording voor de gemaakte keuzes conform de academische en professionele richtlijnen.

---

## 1. Architectuur & Keuzes van Technologieën

Het systeem maakt gebruik van een microservices-achtige opzet bestaande uit een database-container (MySQL) en een verwerkingscontainer (PowerShell/pwsh). Hieronder volgt een gedetailleerde toelichting op de gekozen technologieën en de alternatieven.

### 1.1 Containerisatie: Docker (build)
*   **Waarom Docker?**
    *   **Consistentie:** Garandeert dat de applicatie in elke omgeving (ontwikkeling, testing, productie) identiek draait, ongeacht het host-besturingssysteem.
    *   **Dependency Management:** De specifieke systeemvereisten voor PDF-generatie (zoals `libgdiplus` voor iText) en PowerShell-modules (SimplySql, Pester) worden direct in de image gebouwd.
    *   **Orchestratie:** Dankzij `docker-compose` kunnen de database en applicatie met één commando gekoppeld en opgestart worden met configureerbare netwerken en healthchecks.
*   **Alternatieven:**
    *   *Virtuele Machines (bijv. Vagrant/VirtualBox):* Biedt volledige isolatie, maar heeft een enorme overhead in schijfruimte en opstarttijd vergeleken met Docker-containers.
    *   *Bare-metal installatie:* Vereist dat de gebruiker lokaal MySQL, PowerShell, SimplySql en de benodigde .NET DLL's handmatig installeert, wat foutgevoelig is en de "works on my machine"-problematiek introduceert.

### 1.2 Database: MySQL 8.0
*   **Waarom MySQL?**
    *   **Relationele structuur:** Factuurgegevens zijn inherent gestructureerd (kopgegevens en factuurregels) en lenen zich perfect voor een relationele database.
    *   **Event-handling & Triggers:** MySQL ondersteunt database-triggers (zoals `after_invoice_insert`), waardoor audit logging direct op databaseniveau gegarandeerd is, onafhankelijk van de applicatiecode.
    *   **Ecosysteem:** Uitstekende integratie met PowerShell via de SimplySql-module (die gebruikmaakt van MySQL native client libraries).
*   **Alternatieven:**
    *   *SQLite:* Zeer lichtgewicht en vereist geen aparte database-server. Echter, SQLite is minder geschikt voor gelijktijdige schrijfoperaties en ondersteunt geen geavanceerde triggers en netwerkarchitecturen zoals MySQL.
    *   *PostgreSQL:* Biedt krachtigere features (zoals native XML-validatie), maar brengt extra complexiteit met zich mee die voor deze scope (MVP) niet opweegt tegen de eenvoud van MySQL.

### 1.3 Scripting & Logic: PowerShell Core (pwsh)
*   **Waarom PowerShell?**
    *   **Native XML en XPath ondersteuning:** PowerShell heeft een uitstekende ingebouwde parser (`[xml]`) en ondersteunt XPath-selecties uit de doos, wat cruciaal is voor het verwerken van complexe UBL-XML-facturen.
    *   **Directe .NET-integratie:** Aangezien PowerShell Core op .NET draait, kunnen we naadloos .NET DLL's (zoals iText 7) inladen met `Add-Type` en gebruiken alsof het native cmdlets zijn.
    *   **Object-oriented pipeline:** In tegenstelling tot traditionele shells zoals Bash (die tekststromen verwerken), stuurt PowerShell gestructureerde objecten door de pipeline, wat de betrouwbaarheid van data-operaties vergroot.
*   **Alternatieven:**
    *   *Python:* Een uitstekend alternatief met bibliotheken zoals `lxml` en `ReportLab`. Echter, de integratie met complexe PDF-engines vereist vaak meer boilerplate-code. PowerShell is gekozen omdat het de kerntechnologie van dit vakgebied (Scripting) is en uitstekende XML-validatie-pipelines biedt.
    *   *Bash/Shell Scripting:* Volledig ongeschikt voor het parsen van complexe XML-documenten en het interactie hebben met relationele databases zonder zware, onveilige externe tools.

### 1.4 PDF-generatie: iText 7 (iTextSharp)
*   **Waarom iText 7?**
    *   **HTML-to-PDF Transformatie (`html2pdf`):** In plaats van een PDF pixel-voor-pixel op te bouwen via code (wat extreem tijdrovend en moeilijk te onderhouden is), stelt iText ons in staat om HTML (gegenereerd via XSLT) direct om te zetten naar PDF. Styling gebeurt eenvoudig via standaard CSS.
    *   **Betrouwbaarheid:** iText is de industriestandaard voor enterprise PDF-generatie in Java en .NET. Het biedt volledige controle over pagina-indelingen, fonts en PDF/A-compliance.
*   **Alternatieven:**
    *   *wkhtmltopdf:* Converteert HTML naar PDF met behulp van de WebKit-rendering engine. Hoewel eenvoudig in gebruik, is het project verouderd, wordt het niet meer actief onderhouden, en vereist het een zware externe binaire dependency in de container.
    *   *Puppeteer / Chrome Headless:* Start een headless versie van Google Chrome om de HTML te renderen en op te slaan als PDF. Dit levert de meest moderne CSS-ondersteuning op, maar brengt een gigantische overhead met zich mee (een complete browser in de Docker-container), wat ongewenst is voor een backend-verwerkingsservice.
    *   *QuestPDF:* Een moderne .NET library. Vereist echter dat de layout volledig in C#-code wordt geschreven met een Fluent API. Dit maakt het onmogelijk om flexibele HTML/CSS-templates te gebruiken die door niet-ontwikkelaars aangepast kunnen worden.
    *   *Apache FOP (XSL-FO):* Converteert XML direct naar PDF via XSL-FO. Dit heeft een extreem steile leercurve en vereist complexe, verouderde styling-concepten vergeleken met modern HTML/CSS.

---

## 2. Architectuurontwerp: Entrypoint Script vs. Module

Een belangrijk ontwerpprincipe in dit project is de scheiding van de **uitvoeringslaag** en de **logische laag**:

1.  **De Module (`PeppolProcessor.psm1` / `.psd1`):**
    *   Bevat alle herbruikbare functies (databaseverbinding, XML-validatie, VAT-controle, HTML-transformatie en PDF-conversie).
    *   **Waarom?** Door functies in een module te isoleren, kunnen we ze onafhankelijk van elkaar testen. Unittest-frameworks zoals **Pester** kunnen de functies rechtstreeks inladen en mocken. Dit bevordert de uitbreidbaarheid en onderhoudbaarheid van de code.
2.  **Het Entrypoint Script (`Process-Invoices.ps1`):**
    *   Dit is een heel dun script dat enkel de module importeert en de hoofdfunctie `Start-PeppolProcessor` aanroept.
    *   **Waarom?** Het fungeert als het CLI-startpunt voor de Docker-container (`CMD ["pwsh", "-File", "/app/src/Process-Invoices.ps1"]`). Dit is een best practice in software development: het script configureert de runtime-omgeving (inladen van `.env`-bestanden bij lokaal testen), terwijl de daadwerkelijke business logica veilig in een module is ingekapseld.

---

## 3. Correcte Bronvermelding & Referenties

De implementatie en het ontwerp van dit project zijn gebaseerd op de volgende officiële standaarden en documentatie:

1.  **Peppol BIS Billing 3.0 Standard**
    *   *Beschrijving:* De officiële specificatie van het Peppol-netwerk voor e-facturatie, gebaseerd op de Europese norm EN 16931.
    *   *Referentie:* [Peppol BIS Billing 3.0 / CIUS Rules](https://peppol.eu/what-is-peppol/peppol-profiles/)
    *   *Gebruik in project:* Definitie van verplichte velden zoals de Supplier VAT (BT-31) en Customer VAT (BT-48).
2.  **Oasis Universal Business Language (UBL) 2.1**
    *   *Beschrijving:* Het XML-schema waarop Peppol-facturen zijn gebaseerd.
    *   *Referentie:* [OASIS UBL 2.1 Specification](http://docs.oasis-open.org/ubl/os-UBL-2.1/UBL-2.1.html)
    *   *Gebruik in project:* Structuur van de XML-nodes (`cac:AccountingSupplierParty`, `cac:PartyTaxScheme`, `cbc:CompanyID`) gebruikt in de XPath-queries in `PeppolProcessor.psm1`.
3.  **SimplySql PowerShell Module**
    *   *Beschrijving:* Een PowerShell-module die SQL-interactie objectgebaseerd maakt en SQL-injectie voorkomt door geparametriseerde queries.
    *   *Referentie:* [SimplySql Project Repository](https://github.com/rcbensley/SimplySql)
    *   *Gebruik in project:* Databaseconnectiviteit, schema-initialisatie en status-updates.
4.  **iText 7 for .NET (html2pdf)**
    *   *Beschrijving:* De officiële ontwikkelaarshandleiding voor de HTML-naar-PDF conversiemodule.
    *   *Referentie:* [iText 7 html2pdf Documentation](https://itextpdf.com/en/resources/books/itext-7-converting-html-pdf-pdfhtml)
    *   *Gebruik in project:* Laden van assembly-DLL's en aanroepen van `HtmlConverter::ConvertToPdf` in `Convert-HtmlToPdf`.
5.  **Pester 5 Testing Framework**
    *   *Beschrijving:* Het officiële testframework voor PowerShell.
    *   *Referentie:* [Pester Wiki & Quick Start](https://pester.dev/docs/quick-start)
    *   *Gebruik in project:* Unittests en mock-definities in `tests/Process-Invoices.Tests.ps1` en `tests/Get-Report.Tests.ps1`.
