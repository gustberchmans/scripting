<#
.SYNOPSIS
  Inserts all XML files from the sample_data directory into the database
  so the running server can process them.
#>

# Load .env file if it exists (for local execution)
$envFile = Join-Path $PSScriptRoot "../.env"
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
        $k, $v = $_.Split('=', 2)
        $k = $k.Trim()
        $v = $v.Trim()
        if (-not (Test-Path "Env:\$k")) { Set-Item -Path "Env:\$k" -Value $v }
    }
}

$dbHost = if ($env:DB_HOST) { $env:DB_HOST } else { "127.0.0.1" }
$dbUser = if ($env:DB_USER) { $env:DB_USER } else { "root" }
$dbPassword = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } else { "" }
$dbDatabase = if ($env:DB_DATABASE) { $env:DB_DATABASE } else { "invoices_db" }
$connectionName = "InvoicesDB_Insert"

# Assume script is in /src, so sample_data is in ../sample_data
$sampleDataDir = Join-Path $PSScriptRoot "../sample_data"

try {
    Import-Module SimplySql -ErrorAction Stop
} catch {
    Write-Error "SimplySql module is required."
    exit 1
}

try {
    Write-Host "Connecting to database..."
    if ([string]::IsNullOrEmpty($dbPassword)) {
        $secPass = New-Object System.Security.SecureString
    } else {
        $secPass = ConvertTo-SecureString $dbPassword -AsPlainText -Force
    }
    $cred = New-Object System.Management.Automation.PSCredential($dbUser, $secPass)
    Open-MySqlConnection -Server $dbHost -Credential $cred -ConnectionName $connectionName -Database $dbDatabase -ErrorAction Stop

    $files = Get-ChildItem -Path $sampleDataDir -Filter "*.xml"
    
    foreach ($file in $files) {
        Write-Host "Inserting $($file.Name)..." -NoNewline
        
        $xmlContent = Get-Content $file.FullName -Raw
        # Escape single quotes for SQL safety
        $safeXml = $xmlContent.Replace("'", "''")
        
        # Insert with status 'new' so the server picks it up
        $query = "INSERT INTO invoices (peppol_xml, status) VALUES ('$safeXml', 'new');"
        
        Invoke-SqlUpdate -Query $query -ConnectionName $connectionName -ErrorAction Stop
        Write-Host " Done." -ForegroundColor Green
    }
} catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
} finally {
    try { Close-SqlConnection -ConnectionName $connectionName } catch {}
}