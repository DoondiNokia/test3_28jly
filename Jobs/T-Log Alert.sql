USE [msdb]
GO

/****** Object:  Job [T-Log Alert]    Script Date: 12/26/2019 5:15:14 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 12/26/2019 5:15:15 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'T-Log Alert', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Step]    Script Date: 12/26/2019 5:15:17 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
SET NOCOUNT ON
 
DECLARE @threshold int=5
-- step 1: Create temp table and record sqlperf data
CREATE TABLE #tloglist 
( 
databaseName sysname, 
logSize decimal(18,5), 
logUsed decimal(18,5), 
status INT
) 
 
INSERT INTO #tloglist 
       EXECUTE(''DBCC SQLPERF(LOGSPACE)'') 
 
-- step 2: get T-logs exceeding threshold size in html table format
DECLARE  @xml nvarchar(max)

SELECT @xml = Cast((SELECT databasename AS ''td'',
'''',
logsize AS ''td'',
'''',
logused AS ''td''
 
FROM #tloglist
--- WHERE logsize >= (@threshold*1024) 
FOR xml path(''tr''), elements) AS NVARCHAR(max))
 
-- step 3: Specify table header and complete html formatting
Declare @body nvarchar(max)
SET @body =
''<html><body><H2>High T-Log Size </H2><table border = 1 BORDERCOLOR="Black"> <tr><th> Database </th> <th> LogSize(MB) </th> <th> LogUsed(%) </th> </tr>''
SET @body = @body + @xml + ''</table></body></html>''
 
 


-- step 4: send email if a T-log exceeds threshold
if(@xml is not null)
BEGIN
EXEC msdb.dbo.Sp_send_dbmail
@profile_name = ''hcldb'',
@body = @body,
@body_format =''html'',
@recipients = ''EC-Nokia-DBA@groups.nokia.com'',
@copy_recipients =''mohit.varma.ext@nokia.com'',
@subject = ''ALERT: High T-Log Size US70TWAPP072'';
END
 
DROP TABLE #tloglist 
SET NOCOUNT OFF
', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Schedule', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=2, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190807, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'de013576-9cd8-485c-8e7e-56895d9f0f0f'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

