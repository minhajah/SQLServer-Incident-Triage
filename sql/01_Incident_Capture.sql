/*
 SQL Server Incident Triage - READ-ONLY snapshot
 Run during the application incident, BEFORE SQL restart if safe.
 Compatibility target: SQL Server 2016 SP1+
 Requires suitable DMV permissions (typically VIEW SERVER STATE;
 SQL Server 2022+ may require VIEW SERVER PERFORMANCE STATE).
 Query text and host/login details can be sensitive. Protect exported results.
*/

SET NOCOUNT ON;
SET DEADLOCK_PRIORITY LOW;
SET LOCK_TIMEOUT 5000;

DECLARE @IncidentID nvarchar(100) = N'CHANGE-ME';
DECLARE @CaptureLabel nvarchar(100) = N'First snapshot';

SELECT @IncidentID AS incident_id, @CaptureLabel AS capture_label,
       SYSDATETIMEOFFSET() AS capture_local_with_offset,
       SYSUTCDATETIME() AS capture_utc, @@SERVERNAME AS sql_server,
       SERVERPROPERTY('ProductVersion') AS product_version,
       SERVERPROPERTY('Edition') AS edition;

/* 1. Active requests and blocking */
SELECT SYSDATETIME() AS capture_time, r.session_id, r.request_id,
       s.login_name, s.host_name, s.program_name,
       DB_NAME(r.database_id) AS database_name, r.status, r.command,
       r.start_time, r.cpu_time AS cpu_ms, r.total_elapsed_time AS elapsed_ms,
       r.wait_type, r.wait_time AS wait_ms, r.wait_resource,
       r.blocking_session_id, r.open_transaction_count,
       r.logical_reads, r.reads, r.writes,
       CASE WHEN r.sql_handle IS NULL THEN NULL
            ELSE SUBSTRING(st.text, (r.statement_start_offset/2)+1,
              ((CASE WHEN r.statement_end_offset=-1 THEN DATALENGTH(st.text)
                     ELSE r.statement_end_offset END-r.statement_start_offset)/2)+1)
       END AS running_statement,
       st.text AS batch_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id=r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE s.is_user_process=1
ORDER BY CASE WHEN ISNULL(r.blocking_session_id,0)<>0 THEN 0 ELSE 1 END,
         r.total_elapsed_time DESC;

/* 2. User session counts */
SELECT login_name, host_name, program_name, status,
       COUNT(*) AS session_count,
       SUM(CASE WHEN open_transaction_count>0 THEN 1 ELSE 0 END) AS open_tran_sessions,
       MAX(last_request_end_time) AS latest_last_request_end
FROM sys.dm_exec_sessions
WHERE is_user_process=1
GROUP BY login_name, host_name, program_name, status
ORDER BY session_count DESC;

/* 3. Wait statistics - cumulative since startup / last reset */
SELECT TOP (30) wait_type, waiting_tasks_count,
       wait_time_ms/1000.0 AS wait_seconds,
       signal_wait_time_ms/1000.0 AS signal_wait_seconds,
       CASE WHEN waiting_tasks_count=0 THEN NULL
            ELSE wait_time_ms*1.0/waiting_tasks_count END AS avg_wait_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE N'SLEEP%'
  AND wait_type NOT IN
  (N'BROKER_EVENTHANDLER',N'BROKER_RECEIVE_WAITFOR',N'BROKER_TASK_STOP',
   N'BROKER_TO_FLUSH',N'SQLTRACE_BUFFER_FLUSH',N'CLR_AUTO_EVENT',
   N'CLR_MANUAL_EVENT',N'LAZYWRITER_SLEEP',N'XE_TIMER_EVENT',
   N'XE_DISPATCHER_WAIT',N'REQUEST_FOR_DEADLOCK_SEARCH',N'LOGMGR_QUEUE',
   N'CHECKPOINT_QUEUE')
ORDER BY wait_time_ms DESC;

/* 4. SQL process and host memory */
SELECT physical_memory_in_use_kb/1024 AS sql_process_memory_mb,
       locked_page_allocations_kb/1024 AS locked_pages_mb,
       memory_utilization_percentage, page_fault_count,
       process_physical_memory_low, process_virtual_memory_low
FROM sys.dm_os_process_memory;

SELECT total_physical_memory_kb/1024 AS host_total_memory_mb,
       available_physical_memory_kb/1024 AS host_available_memory_mb,
       system_memory_state_desc
FROM sys.dm_os_sys_memory;

/* 5. Worker threads and scheduler queues */
SELECT max_workers_count,
       (SELECT COUNT(*) FROM sys.dm_os_workers) AS worker_count,
       (SELECT COUNT(*) FROM sys.dm_os_workers WHERE state=N'RUNNING') AS running_workers,
       (SELECT COUNT(*) FROM sys.dm_os_workers WHERE state=N'RUNNABLE') AS runnable_workers
FROM sys.dm_os_sys_info;

SELECT scheduler_id, status, current_tasks_count, runnable_tasks_count,
       current_workers_count, active_workers_count, work_queue_count, load_factor
FROM sys.dm_os_schedulers
WHERE status=N'VISIBLE ONLINE'
ORDER BY scheduler_id;

/* 6. Database file I/O - cumulative since startup */
SELECT DB_NAME(v.database_id) AS database_name, f.name AS logical_file_name,
       f.type_desc, f.physical_name, v.num_of_reads, v.io_stall_read_ms,
       CASE WHEN v.num_of_reads=0 THEN 0
            ELSE v.io_stall_read_ms*1.0/v.num_of_reads END AS avg_read_latency_ms,
       v.num_of_writes, v.io_stall_write_ms,
       CASE WHEN v.num_of_writes=0 THEN 0
            ELSE v.io_stall_write_ms*1.0/v.num_of_writes END AS avg_write_latency_ms
FROM sys.dm_io_virtual_file_stats(NULL,NULL) v
JOIN sys.master_files f ON f.database_id=v.database_id AND f.file_id=v.file_id
ORDER BY v.io_stall_read_ms+v.io_stall_write_ms DESC;

/* 7. Database state and transaction log space */
SELECT name, state_desc, user_access_desc, recovery_model_desc,
       log_reuse_wait_desc, compatibility_level, is_read_only,
       is_auto_close_on, is_auto_shrink_on
FROM sys.databases ORDER BY name;

DBCC SQLPERF(LOGSPACE);

/* 8. TempDB current space usage */
USE tempdb;
SELECT SUM(unallocated_extent_page_count)*8.0/1024 AS free_space_mb,
       SUM(version_store_reserved_page_count)*8.0/1024 AS version_store_mb,
       SUM(user_object_reserved_page_count)*8.0/1024 AS user_objects_mb,
       SUM(internal_object_reserved_page_count)*8.0/1024 AS internal_objects_mb
FROM sys.dm_db_file_space_usage;
USE master;

/* 9. Optional Always On AG health */
IF SERVERPROPERTY('IsHadrEnabled')=1
BEGIN
    SELECT ag.name AS availability_group, ar.replica_server_name,
           ars.role_desc, ars.operational_state_desc, ars.connected_state_desc,
           ars.synchronization_health_desc, drs.database_name,
           drs.synchronization_state_desc, drs.synchronization_health_desc AS db_sync_health,
           drs.log_send_queue_size, drs.redo_queue_size, drs.last_commit_time
    FROM sys.availability_groups ag
    JOIN sys.availability_replicas ar ON ar.group_id=ag.group_id
    LEFT JOIN sys.dm_hadr_availability_replica_states ars ON ars.replica_id=ar.replica_id
    LEFT JOIN sys.dm_hadr_database_replica_states drs ON drs.replica_id=ar.replica_id
    ORDER BY ag.name, ar.replica_server_name, drs.database_name;
END;

/* 10. SQL Server startup time */
SELECT sqlserver_start_time,
       DATEDIFF(MINUTE,sqlserver_start_time,SYSDATETIME()) AS uptime_minutes
FROM sys.dm_os_sys_info;

/* Optional SQL error-log searches - run individually as needed:
EXEC master.dbo.sp_readerrorlog 0,1,N'Error';
EXEC master.dbo.sp_readerrorlog 0,1,N'timeout';
EXEC master.dbo.sp_readerrorlog 0,1,N'I/O requests';
EXEC master.dbo.sp_readerrorlog 0,1,N'memory';
EXEC master.dbo.sp_readerrorlog 0,1,N'connection';

Also review Windows Event Viewer > Windows Logs > System and Application.
Do not clear wait stats or restart SQL Server just to create a clean baseline.
*/
