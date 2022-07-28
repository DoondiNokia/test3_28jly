USE [msdb]
GO

/****** Object:  Job [DeleteObsoleteBackupsFromDisk]    Script Date: 12/26/2019 4:41:49 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [Database Maintenance]    Script Date: 12/26/2019 4:41:49 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DeleteObsoleteBackupsFromDisk', 
		@enabled=0, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'This job delete from disk all backups (except those containing DND or donotdelete in the path or in the file name) that are older than 15 days', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'CID_Support', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [DeleteObsoleteBackups]    Script Date: 12/26/2019 4:41:51 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'DeleteObsoleteBackups', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'set nocount on
use msdb
PRINT ''DELETE OF OBSOLETE BACKUPS TO DISK'' 
declare @currentdatetime nvarchar(1000)
select @currentdatetime=(SELECT CONVERT(VARCHAR(26), GETDATE(), 109))
print ''Start time :''+@currentdatetime+''''

create table #obsoletebackuptodisk (output varchar(7999))	


Declare GetResultSet cursor FAST_FORWARD  For
select distinct(m.physical_device_name)
FROM msdb.dbo.[backupmediafamily] m
JOIN msdb.dbo.[backupset] b ON b.media_set_id = m.media_set_id
WHERE  
b.[backup_finish_date]> GETDATE() - 30 and
b.[backup_finish_date]<= GETDATE() - 15  and
m.device_type in (2,102) and
m.[physical_device_name] not like ''%DND%'' and
m.[physical_device_name] not like ''%donotdelete%''
    declare @backupfile varchar(7999)
   Open GetResultSet
Fetch from GetResultSet into @backupfile 	
While @@Fetch_Status=0
Begin
   declare @SQL1 varchar(7999)
	select @SQL1 = ''insert into #obsoletebackuptodisk (output) exec master..xp_cmdshell ''''del /Q "''+@backupfile +''"''''''
	exec (@SQL1)
	IF @@ERROR <> 0 goto req
	Fetch Next From GetResultSet into @backupfile
End

Close GetResultSet
DeAllocate GetResultSet

set nocount on 
if (select count(*) from #obsoletebackuptodisk)=0
begin 
print ''There was no backup to disk done in the last 30 days''
goto fin
end

IF OBJECT_ID(''tempdb..#obsoletebackuptodisk'') IS NULL
begin
print ''Could not delete obsolete files due to server restrictions''
goto fin
end

if (select count(*) from #obsoletebackuptodisk where 
output <>''NULL'' 
and output not like ''%Could Not Find%'' 
and output not like ''%The system cannot find the file specified%''
and output not like ''%bak%'' 
and output not like ''%diff%'' 
and output not like ''%trn%''
or output like ''%Could not find stored procedure%'') =0 
begin
print ''Delete of obsolete backups completed successfully''
goto fin
end

if (select count(*) from #obsoletebackuptodisk where 
output <>''NULL'' 
and output not like ''%Could Not Find%'' 
and output not like ''%The system cannot find the file specified%''
and output not like ''%bak%'' 
and output not like ''%diff%'' 
and output not like ''%trn%'') >0
begin 
print ''Errors in Deleting obsolete backups - see details below''  
select convert (varchar(100),output) from #obsoletebackuptodisk where 
output <>''NULL'' 
and output not like ''%Could Not Find%'' 
and output not like ''%The system cannot find the file specified%''
and output not like ''%bak%'' 
and output not like ''%diff%'' 
and output not like ''%trn%''
goto fin
end

req:
print ''Cannot delete obsolete backups''
goto fin

fin:
drop table #obsoletebackuptodisk
declare @currentdatetime2 nvarchar(1000)
select @currentdatetime2=(SELECT CONVERT(VARCHAR(26), GETDATE(), 109))
print ''End time :''+@currentdatetime2+''''	
select ''''




', 
		@database_name=N'master', 
		@output_file_name=N'E:\SQLSYS\MSSQL\MSSQL10_50.MSSQLSERVER\MSSQL\Log\DeleteObsoleteBackups.txt', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Daily_06:00PM', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20151204, 
		@active_end_date=99991231, 
		@active_start_time=180000, 
		@active_end_time=235959, 
		@schedule_uid=N'1848a6cd-28c5-4fdd-8658-dde6c0fd8966'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

