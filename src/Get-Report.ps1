<#
.SYNOPSIS
  Generates an HTML report of the invoice processing status.
  Fulfills the "Visual Interface/Reporting" extra requirement.
#>

$dbHost = $env:DB_HOST
$dbUser = $env:DB_USER
$dbPassword = $env:DB_PASSWORD
$dbDatabase = $env:DB_DATABASE
$connectionName = "InvoicesDB_Report"
$reportPath = "/app/output/status_report.html"

try {
    Import-Module SimplySql -ErrorAction Stop
    
    $secPass = ConvertTo-SecureString $dbPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($dbUser, $secPass)
    Open-MySqlConnection -Server $dbHost -Credential $cred -ConnectionName $connectionName -Database $dbDatabase -ErrorAction Stop

    # Get Statistics
    $stats = Invoke-SqlQuery -Query "SELECT status, COUNT(*) as count FROM invoices GROUP BY status" -ConnectionName $connectionName
    
    # Get Recent Errors
    $errors = Invoke-SqlQuery -Query "SELECT id, processed_at, error_message FROM invoices WHERE status = 'error' ORDER BY id DESC LIMIT 10" -ConnectionName $connectionName

    # Build HTML
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Peppol Processing Report</title>
    <style>
        body { font-family: sans-serif; padding: 20px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .status-new { color: blue; }
        .status-processed { color: green; }
        .status-error { color: red; }
    </style>
</head>
<body>
    <h1>System Status Report</h1>
    <p>Generated at: $(Get-Date)</p>

    <h2>Overview</h2>
    <table>
        <tr><th>Status</th><th>Count</th></tr>
        $($stats | ForEach-Object { "<tr><td>$($_.status)</td><td>$($_.count)</td></tr>" })
    </table>

    <h2>Recent Errors</h2>
    <table>
        <tr><th>ID</th><th>Time</th><th>Error Message</th></tr>
        $($errors | ForEach-Object { "<tr><td>$($_.id)</td><td>$($_.processed_at)</td><td class='status-error'>$($_.error_message)</td></tr>" })
    </table>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "Report generated at: $reportPath" -ForegroundColor Green

} catch {
    Write-Error "Failed to generate report: $($_.Exception.Message)"
} finally {
    try { Close-SqlConnection -ConnectionName $connectionName } catch {}
}