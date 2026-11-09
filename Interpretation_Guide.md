# Interpretation Guide

## Blocking
`blocking_session_id` identifies the session currently blocking a request. Find the head blocker and inspect its open transaction and owner before considering termination. A snapshot can miss short-lived blocking.

## Wait statistics
Waits accumulate over time. Compare two snapshots and calculate deltas; a lifetime ranking is not a live diagnosis.
- `LCK_M_*`: lock waits
- `PAGEIOLATCH_*`: data page I/O waits
- `WRITELOG`: transaction log flush waits
- `RESOURCE_SEMAPHORE`: query memory grant waits
- `THREADPOOL`: worker-thread availability
- `SOS_SCHEDULER_YIELD`: possible CPU scheduling pressure; corroborate
- `ASYNC_NETWORK_IO`: SQL Server waiting for client/network consumption
- `HADR_SYNC_COMMIT`: synchronous AG commit acknowledgement latency

## Memory
Low-memory flags are useful signals. SQL Server using substantial memory is not automatically a problem. Correlate with OS available memory, max server memory, memory clerks and grant waits.

## Worker threads
A high worker count alone does not prove exhaustion. Investigate THREADPOOL, work queues, active requests and blocking together.

## File I/O
The script's average latency is cumulative since startup. Compare read/write counts and stall milliseconds between captures to estimate incident-period latency. Correlate with OS/storage telemetry.

## Application vs SQL Server
A successful `SELECT 1` proves only basic connectivity and execution. One application may have a connection-pool, stale-connection, long-transaction, query-timeout or application-thread issue while other applications remain healthy.

## Availability Groups
Check replica role, connection state, synchronization health, log-send queue and redo queue. A healthy SQL instance does not guarantee the application is connecting to the intended listener or replica.
