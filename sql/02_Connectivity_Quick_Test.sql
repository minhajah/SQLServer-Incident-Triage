/*
 Basic SQL connectivity test.
 Run from the application server connection path, using the intended database/login.
 This does not validate the application's stored procedure, connection pool or network
 behavior beyond this specific connection.
*/
SET NOCOUNT ON;

SELECT SYSDATETIMEOFFSET() AS server_time,
       @@SERVERNAME AS server_name,
       DB_NAME() AS current_database,
       ORIGINAL_LOGIN() AS original_login,
       SUSER_SNAME() AS effective_login,
       @@SPID AS session_id;

SELECT 1 AS basic_query_test, GETDATE() AS query_time;

SELECT name, state_desc, user_access_desc
FROM sys.databases
WHERE name=DB_NAME();
