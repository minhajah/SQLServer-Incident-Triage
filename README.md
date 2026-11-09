# SQL Server Incident Triage

Read-only SQL Server diagnostic toolkit for application hangs, connection failures, timeouts, blocking, and suspected resource pressure.

## Contents
- `sql/01_Incident_Capture.sql` — active requests, blocking, sessions, waits, memory, workers, file I/O, database/log state, TempDB, optional AG health, startup time.
- `sql/02_Connectivity_Quick_Test.sql` — basic connection and query test.
- `docs/Incident_Runbook.md` — what to collect and who to involve.
- `docs/Interpretation_Guide.md` — common signals and cautions.

## Quick start
1. Connect to the affected instance using SSMS.
2. Open `sql/01_Incident_Capture.sql`.
3. Set the incident ID and capture label near the top.
4. Run it while the issue is happening, before restarting SQL Server if safe.
5. Save **all** result sets with the incident timestamp.
6. If the issue continues, run it again after 2–5 minutes and compare cumulative counters.
7. Ask application and infrastructure teams to preserve logs for the same time window.

## Permissions / compatibility
Designed for SQL Server 2016 SP1 and later. The executing login typically needs `VIEW SERVER STATE`; SQL Server 2022+ may require `VIEW SERVER PERFORMANCE STATE` for some DMV access. AG checks are conditional.

## Important cautions
- Wait statistics and file I/O counters are cumulative since startup or last reset. Compare two captures; one snapshot is not an incident-period measurement.
- Query text, hostnames, login names and program names may be sensitive. Restrict access to captured output and sanitize before sharing.
- These scripts do not kill sessions, change configuration, clear counters, or restart services.
- `SELECT 1` confirms basic SQL execution only; it does not prove the application query or connection pool is healthy.
- If an emergency restart is necessary, capture what is safe first. Do not delay critical recovery.

## GitHub security
Use a private repository if scripts or examples contain internal details. Never commit live diagnostic output, credentials, connection strings, customer data, or production query literals.

Test in a non-production environment before operational use.
