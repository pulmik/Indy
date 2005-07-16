{
  $Project$
  $Workfile$
  $Revision$
  $DateUTC$
  $Id$

  This file is part of the Indy (Internet Direct) project, and is offered
  under the dual-licensing agreement described on the Indy website.
  (http://www.indyproject.org/)

  Copyright:
   (c) 1993-2005, Chad Z. Hower and the Indy Pit Crew. All rights reserved.
}
{
  $Log$
}
{
{   Rev 1.12    2004.02.03 4:17:06 PM  czhower
{ For unit name changes.
}
{
{   Rev 1.11    2003.10.24 12:59:20 PM  czhower
{ Name change
}
{
{   Rev 1.10    2003.10.21 12:19:00 AM  czhower
{ TIdTask support and fiber bug fixes.
}
{
{   Rev 1.9    2003.10.11 5:49:50 PM  czhower
{ -VCL fixes for servers
{ -Chain suport for servers (Super core)
{ -Scheduler upgrades
{ -Full yarn support
}
{
{   Rev 1.8    2003.09.19 10:11:20 PM  czhower
{ Next stage of fiber support in servers.
}
{
{   Rev 1.7    2003.09.19 11:54:32 AM  czhower
{ -Completed more features necessary for servers
{ -Fixed some bugs
}
{
{   Rev 1.6    2003.09.18 4:10:26 PM  czhower
{ Preliminary changes for Yarn support.
}
{
    Rev 1.5    7/6/2003 8:04:08 PM  BGooijen
  Renamed IdScheduler* to IdSchedulerOf*
}
{
    Rev 1.4    7/5/2003 11:49:06 PM  BGooijen
  Cleaned up and fixed av in threadpool
}
{
    Rev 1.3    4/15/2003 10:56:08 PM  BGooijen
  fixes
}
{
    Rev 1.2    3/13/2003 10:18:34 AM  BGooijen
  Server side fibers, bug fixes
}
{
    Rev 1.1    1/23/2003 7:28:46 PM  BGooijen
}
{
{   Rev 1.0    1/17/2003 03:29:58 PM  JPMugaas
{ Renamed from ThreadMgr for new design.
}
{
{   Rev 1.0    11/13/2002 09:01:46 AM  JPMugaas
}
{
2002-06-23 -Andrew P.Rybin
  -2 deadlock fix (and also in IdThread)
}
unit IdSchedulerOfThreadPool;

interface

uses
  IdContext,
  IdScheduler,
  IdSchedulerOfThread,
  IdSys,
  IdThread,
  IdThreadSafe,
  IdYarn;

type

  TIdSchedulerOfThreadPool = class(TIdSchedulerOfThread)
  protected
    FPoolSize: Integer;
    FThreadPool: TIdThreadSafeList;
  public
    function AcquireYarn: TIdYarn;override;
    destructor Destroy; override;
    procedure InitComponent; override;
    procedure Init; override;
    function NewThread: TIdThreadWithTask;override;
    procedure ReleaseYarn(AYarn: TIdYarn);override;
    procedure TerminateAllYarns;override;
  published
    //TODO: Poolsize is only looked at during loading and when threads are
    // needed. Probably should add an Active property to schedulers like
    // servers have.
    property PoolSize: Integer read FPoolSize write FPoolSize default 0;
  End;

implementation

uses
  IdGlobal;

type

  TIdYarnOfThreadAccess = class(TIdYarnOfThread)
  end;

destructor TIdSchedulerOfThreadPool.Destroy;
begin
  inherited Destroy;
  // Must be after, inherited calls TerminateThreads
  Sys.FreeAndNil(FThreadPool);
end;

function TIdSchedulerOfThreadPool.AcquireYarn: TIdYarn;
var
  LThread: TIdThreadWithTask;
begin
  LThread := TIdThreadWithTask(FThreadPool.Pull);
  if LThread = nil then begin
    LThread := NewThread;
  end;
  Result := NewYarn(LThread);
  ActiveYarns.Add(Result);
end;

procedure TIdSchedulerOfThreadPool.ReleaseYarn(AYarn: TIdYarn);
//only gets called from YarnOf(Fiber/Thread).Destroy
var
  LThread: TIdThreadWithTask;
begin
  //take posession of the thread
  LThread:=TIdYarnOfThread(aYarn).Thread;
  TIdYarnOfThreadAccess(AYarn).FThread:=nil;
  //Currently LThread can =nil. Is that a valid condition?
  //Assert(LThread<>nil);

  // inherited removes from ActiveYarns list and destroys yarn
  inherited ReleaseYarn(AYarn);

  with FThreadPool.LockList do try
    if (Count < PoolSize) and (LThread<>nil) then begin
      Add(LThread);
      LThread := nil;
    end;
  finally FThreadPool.UnlockList; end;
  // Was not redeposited to pool, need to destroy it
  if LThread <> nil then begin
    LThread.Terminate;
    LThread.Resume;
    LThread.WaitFor;
    Sys.FreeAndNil(LThread);
  end;
end;

procedure TIdSchedulerOfThreadPool.TerminateAllYarns;
begin
  // inherited will kill off ActiveYarns
  inherited TerminateAllYarns;
  // ThreadPool is nil if never Initted
  if FThreadPool <> nil then begin
    // Now we have to kill off the pooled threads
    with FThreadPool.LockList do try
      while Count > 0 do begin
        with TIdThreadWithTask(Items[0]) do begin
          Terminate;
          Resume;
          WaitFor;
          Free;
        end;
        Delete(0);
      end;
    finally FThreadPool.UnlockList; end;
  end;
end;

procedure TIdSchedulerOfThreadPool.Init;
begin
  inherited Init;
  Assert(FThreadPool<>nil);

  if not IsDesignTime then begin
    if PoolSize > 0 then begin
      with FThreadPool.LockList do try
        while Count < PoolSize do begin
          Add(NewThread);
        end;
      finally FThreadPool.UnlockList; end;
    end;
  end;
end;

function TIdSchedulerOfThreadPool.NewThread: TIdThreadWithTask;
begin
  Result := inherited NewThread;
  Result.StopMode := smSuspend;
end;

procedure TIdSchedulerOfThreadPool.InitComponent;
begin
  inherited;
  FThreadPool := TIdThreadSafeList.Create;
end;

end.
