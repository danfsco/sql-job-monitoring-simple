# SQL job reports in OneDrive + Copilot

Two schedules: **Windows Task Scheduler collects reports into OneDrive first;
Copilot Cowork automation reviews them and sends a Teams summary afterward.**

## 1. Test

Create a `SQL Job Reports` folder in your approved OneDrive. Open PowerShell in
this script's folder and run, replacing the server and local OneDrive path:

```powershell
.\Get-FailedSqlJobs.ps1 -ServerInstance 'localhost' -OutputDirectory 'C:\Users\YOUR_USER\OneDrive - YOUR_ORG\SQL Job Reports'
```

Windows authentication is the default. For SQL authentication, add
`-SqlCredential (Get-Credential)`; the server must allow SQL authentication.
For local development self-signed certificates only, add `-TrustServerCertificate`.

## 2. Schedule report collection first

In Windows Task Scheduler, create a **Daily** task using **Run only when user is
logged on**. Program: `powershell.exe` (or `pwsh.exe`). Arguments, on one line:

```text
-NoProfile -NonInteractive -File "C:\FULL_PATH\Get-FailedSqlJobs.ps1" -ServerInstance "localhost" -OutputDirectory "C:\Users\YOUR_USER\OneDrive - YOUR_ORG\SQL Job Reports"
```

Replace the paths and server. Schedule for **8:00 AM**, for example, and run once
to confirm a report appears and syncs to OneDrive.
Keep the computer on, your account logged in, and OneDrive syncing. Scheduled SQL
authentication needs a credential-store wrapper; it cannot use a password prompt.

## 3. Ask Copilot, then create its automation

After OneDrive finishes syncing, attach or reference the report files in
Microsoft 365 Copilot and ask:

> Summarize the SQL job failures in these reports. Which failures recur, and what
> should I investigate first?

Then select **Cowork** and request a recurring automation, using your OneDrive
folder's **web link**, not its local Windows path:

> Every day at 8:30 AM, review today's newest sql-job-failures-*.txt report in
> [SQL Job Reports folder link]. Summarize failures, recurring issues, and
> recommended next steps. Send me a Teams message with a link to the report.
> If today's report is missing, tell me; do not treat missing data as success.

Review and confirm the recurring task, connect OneDrive/SharePoint and Teams
when prompted, and verify a test Teams message. Allow time between schedules for
collection and sync; confirm the time zone. Cowork needs access to the folder
and automation tools; it does not run the local PowerShell script.

Screenshots: [Create](setup-cowork-automation-1.png) |
[Configure](setup-cowork-automation-2.png) |
[Teams result](setup-cowork-automation-3-teams-message.png).

**Requires:** PowerShell 5.1/7, SQL Server with SQL Agent, and permission to read
`msdb.dbo.sysjobs`/`sysjobhistory` and execute `msdb.dbo.agent_datetime`.
No extra modules; no Entra/MFA or Azure SQL Database support.
Reports cover the previous 24 hours, are read-only, and accumulate.
No failures found does not prove jobs ran successfully.
