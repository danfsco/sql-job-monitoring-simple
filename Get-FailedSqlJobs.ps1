[CmdletBinding(DefaultParameterSetName = 'Windows')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$ServerInstance = 'localhost',
    [Parameter(Mandatory, ParameterSetName = 'Sql')]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]$SqlCredential,
    [ValidateRange(1, 168)]
    [int]$Hours = 24,
    [switch]$TrustServerCertificate,
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'reports'),
    [ValidateNotNullOrEmpty()]
    [string]$OneDriveFolder
)

$ErrorActionPreference = 'Stop'
if ($OneDriveFolder -and -not (Test-Path -LiteralPath $OneDriveFolder -PathType Container)) {
    throw "OneDrive folder does not exist: $OneDriveFolder. Select an existing folder inside your synced OneDrive."
}
$capturedAt = Get-Date
$report = [System.Collections.Generic.List[string]]::new()
$report.Add("SQL Agent failure history: $ServerInstance")
$report.Add("Checked: $($capturedAt.ToString('o')); lookback: $Hours hours (SQL Server local time).")
$report.Add('Failed steps and job outcomes may overlap; a failed step may belong to a job that later succeeded.')
$report.Add('')
$settings = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$settings['Data Source'] = $ServerInstance
$settings['Initial Catalog'] = 'msdb'
$settings['Integrated Security'] = ($PSCmdlet.ParameterSetName -eq 'Windows')
$settings['Encrypt'] = $true
$settings['TrustServerCertificate'] = $TrustServerCertificate.IsPresent
$settings['Connect Timeout'] = 10
$connection = [System.Data.SqlClient.SqlConnection]::new($settings.ConnectionString)
$sqlPassword = $null

try {
    if ($PSCmdlet.ParameterSetName -eq 'Sql') {
        $sqlPassword = $SqlCredential.Password.Copy()
        $sqlPassword.MakeReadOnly()
        $connection.Credential = [System.Data.SqlClient.SqlCredential]::new($SqlCredential.UserName, $sqlPassword)
    }
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = @'
SELECT
    j.name AS Job,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS Started,
    CASE WHEN h.step_id = 0 THEN '(job outcome)' ELSE h.step_name END AS Step,
    h.message AS Error
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE h.run_status = 0
  AND h.run_date > 0
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time)
      >= DATEADD(hour, -@Hours, GETDATE())
ORDER BY h.instance_id DESC;
'@
    $null = $command.Parameters.Add('@Hours', [System.Data.SqlDbType]::Int)
    $command.Parameters['@Hours'].Value = $Hours
    $reader = $command.ExecuteReader()
    try {
        $found = $false
        while ($reader.Read()) {
            $found = $true
            $entry = [pscustomobject]@{
                Job = $reader['Job']
                Started = $reader['Started']
                Step = $reader['Step']
                Error = $reader['Error']
            } | Format-List | Out-String -Width 4096
            $report.Add($entry.TrimEnd())
        }
        if (-not $found) {
            $report.Add("No failures found in visible SQL Agent history for the last $Hours hours. This does not prove jobs ran successfully.")
        }
    }
    finally { $reader.Dispose() }
}
finally {
    $connection.Dispose()
    if ($null -ne $sqlPassword) { $sqlPassword.Dispose() }
}

$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$fileName = "sql-job-failures-$($capturedAt.ToString('yyyyMMdd-HHmmss-fffffff')).txt"
$reportPath = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath $fileName
$report | Set-Content -LiteralPath $reportPath -Encoding utf8
$report | Write-Output
Write-Host "Report saved: $reportPath"

if ($OneDriveFolder) {
    $destination = Join-Path (Resolve-Path -LiteralPath $OneDriveFolder).ProviderPath $fileName
    if ($reportPath -ne $destination) {
        Copy-Item -LiteralPath $reportPath -Destination $destination -ErrorAction Stop
    }
    Write-Host "Report available in local OneDrive folder: $destination"
}
