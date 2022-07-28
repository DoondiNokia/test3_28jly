USE [msdb]
GO

/****** Object:  Job [Index Optomize - Stocklist]    Script Date: 12/26/2019 5:00:46 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 12/26/2019 5:00:47 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Index Optomize - Stocklist', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'rebuild tables or indexes with > 30 fragmentation percentage', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'NSN-INTRA\beitman', 
		@notify_email_operator_name=N'CID_Support', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Rebuild top 150 table/index with largest fragmentation]    Script Date: 12/26/2019 5:00:48 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Rebuild top 150 table/index with largest fragmentation', 
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
IF  OBJECT_ID(''tempdb..#TMP_IndexRebuild'', ''table'') IS NOT NULL DROP table  #TMP_IndexRebuild
SELECT  top(150) OBJECT_NAME(IDX.OBJECT_ID) AS Table_Name, 
IDX.name AS Index_Name, 
IDXPS.index_type_desc AS Index_Type, 
IDXPS.avg_fragmentation_in_percent  Fragmentation_Percentage
,ROW_NUMBER() over(partition by ''n'' order by IDXPS.avg_fragmentation_in_percent desc) rnum
into #TMP_IndexRebuild
FROM sys.dm_db_index_physical_stats(DB_ID(''stocklist''), NULL, NULL, NULL, NULL) IDXPS 
INNER JOIN sys.indexes IDX  ON IDX.object_id = IDXPS.object_id 
AND IDX.index_id = IDXPS.index_id 
where IDXPS.avg_fragmentation_in_percent >30
ORDER BY Fragmentation_Percentage DESC

--select * from #TMP_IndexRebuild
declare @ix_name varchar(100), @i int, @tbl_name varchar(100), @ix_type varchar(100), @imax int, @SQL nvarchar(2000)

select @i = 1, @imax= MAX(rnum) from #TMP_IndexRebuild

while @i <= @imax
Begin
	select @ix_name = Index_Name, @tbl_name = Table_Name, @ix_type = Index_Type from #TMP_IndexRebuild where rnum = @i
	
	if (select ISNULL( len(@ix_name),0))>0 sELECT @SQL = ''ALTER INDEX '' + @ix_name + '' ON '' + @tbl_name + '' rebuild''
	--if type is heap rebuild the table other wise rebuild the index
	if @ix_type =''heap'' select @SQL = ''ALTER TABLE '' + @tbl_name + '' Rebuild''
	
	--print @SQL
	EXEC sp_executeSQL @SQL
	
	SELECT @i = @i+1 

end

', 
		@database_name=N'Stocklist', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Rebuild schedule 1', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190312, 
		@active_end_date=99991231, 
		@active_start_time=10000, 
		@active_end_time=235959, 
		@schedule_uid=N'8973aecb-8c4a-4c7a-86ac-bde98701d57f'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

