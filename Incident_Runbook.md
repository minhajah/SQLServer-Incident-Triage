# Incident Runbook

## 1. Record the incident facts
- Ticket/incident ID and exact start time (include timezone)
- Application, module, application server, SQL instance and database
- Exact error text and error number
- Scope: one user, some users, all users, one application or multiple applications
- Whether an application-service or SQL-service restart was attempted

Distinguish a connection/login timeout from a command/query timeout.

## 2. Capture SQL evidence before restart (if safe)
1. Connect to the affected SQL instance in SSMS.
2. Run `sql/01_Incident_Capture.sql`.
3. Save every result set with the incident ID and timestamp.
4. If the issue continues, repeat after 2-5 minutes.
5. Run relevant error-log searches at the bottom of the script.
6. Review Windows Event Viewer with the infrastructure team.

Do not kill sessions or clear counters just to collect evidence.

## 3. Ask the application team
- Can the application host connect to the SQL instance?
- Can it execute a simple query?
- Does the actual application query/stored procedure fail?
- Are all users affected?
- Does restarting only the application service restore service?
- What is the exact exception, timestamp, command timeout and connection timeout?
- Are connection-pool limits or retry limits being reached?

## 4. Ask infrastructure to correlate the same time window
Check Windows CPU, available memory, disk/storage latency, network latency, packet loss, DNS, firewall, VM/host contention and Windows System/Application event logs.

## 5. Initial investigation map
| Evidence | Investigate |
|---|---|
| Many requests blocked by one SPID | Head blocker and open transaction |
| High CPU / runnable tasks | Expensive queries, plan regression, CPU pressure |
| THREADPOOL / work queue | Worker-thread pressure and request volume |
| RESOURCE_SEMAPHORE | Query memory grants |
| High file I/O latency | Storage path and workload |
| WRITELOG | Transaction log flush latency |
| LCK_M_* | Blocking and transaction duration |
| ASYNC_NETWORK_IO | Client consumption, result size and network |
| SSMS works but application cannot connect | Application-host network, DNS, firewall, TLS, authentication |
| SQL evidence looks normal | Continue with application, OS, network and storage evidence |

These are clues, not proof of root cause.

## 6. Close the incident
Document root cause (or what remains unproven), supporting evidence, recovery action, permanent fix, owner, monitoring change and recurrence status.
