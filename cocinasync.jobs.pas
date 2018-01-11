unit cocinasync.jobs;

interface

uses System.SysUtils, System.SyncObjs, Cocinasync.Collections, cocinasync.monitor;

type
  EJobExecutionFailure = class(Exception)

  end;

  IJob = interface
    procedure SetupJob;
    procedure ExecuteJob;
    procedure FinishJob;
    function Wait(Timeout : Cardinal = INFINITE) : boolean; overload;
    procedure Wait(var Completed : boolean; Timeout : Cardinal = INFINITE); overload;
    procedure RaiseExceptionIfExists;
    function ExecutionTime : Cardinal;
    function Name : string;
  end;

  IJob<T> = interface(IJob)
    function Result : T;
  end;

  TJobQueue = class(TQueue<IJob>)
  public
    function WaitForAll(Timeout : Cardinal = INFINITE) : boolean; inline;
    procedure Abort;
  end;

  TJobQueue<T> = class(TQueue<IJob<T>>)
  public
    function WaitForAll(Timeout : Cardinal = INFINITE) : boolean; inline;
    procedure Abort;
  end;

  TJobHandler = reference to procedure(const Job : IJob);
  IJobs = interface
    function Queue(const DoIt : TProc) : IJob; overload;
    function Queue(const Job : IJob) : IJob; overload;
    procedure WaitForAll(Timeout : Cardinal = INFINITE);
    function Name : string;
  end;

  TJobException = record
    Clss : String;
    Msg : String;
    Triggered : boolean;
    class function Init : TJobException; static;
    procedure Update(E: Exception);
    procedure RaiseExceptionIfExists;
  end;

  TDefaultJob<T> = class(TInterfacedObject, IJob, IJob<T>)
  private
    FExecutionTime : Cardinal;
    FProcToExecute : TProc;
    FFuncToExecute : TFunc<T>;
    FEvent : TEvent;
    FResult : T;
    FException : TJobException;
    FName : string;
    procedure SetEvent; inline;
  public
    constructor Create(ProcToExecute : TProc; FuncToExecute : TFunc<T>; AName : string); reintroduce; virtual;
    destructor Destroy; override;

    procedure ExecuteJob; inline;
    procedure SetupJob; inline;
    procedure FinishJob; inline;
    function Wait(Timeout : Cardinal = INFINITE) : boolean; overload; inline;
    procedure Wait(var Completed : boolean; Timeout : Cardinal = INFINITE); overload; inline;
    function Result : T; inline;
    procedure RaiseExceptionIfExists;
    function ExecutionTime : Cardinal;
    function Name : string;
  end;

  TJobManager = class
  private
    class var FMonitor : IJobMonitor;
  public
    class procedure RegisterMonitor(Monitor : IJobMonitor);
    class procedure UnregisterMonitor(Monitor : IJobMonitor);
    class procedure ShowMonitor;
    class procedure HideMonitor;
    class function CreateJobs(RunnerCount : Cardinal = 0; MaxJobs : Integer = 4096; const Name : string = '') : IJobs;
    class function Job(const AJob : TProc; const AName : string = '') : IJob; overload; inline;
    class function Job<T>(const AJob : TFunc<T>; const AName : string = '') : IJob<T>; overload; inline;
    class function Execute(const AJob : TProc; AJobs : IJobs = nil; const AName : string = '') : IJob; overload; inline;
    class function Execute<T>(const AJob : TFunc<T>; AJobs : IJobs = nil; const AName : string = '') : IJob<T>; overload; inline;
    class function Execute(const AJob : TProc; AQueue : TJobQueue; AJobs : IJobs = nil; const AName : string = '') : IJob; overload; inline;
    class function Execute<T>(const AJob : TFunc<T>; AQueue : TJobQueue<T>; AJobs : IJobs = nil; const AName : string = '') : IJob<T>; overload; inline;
  end;


var
  Jobs : IJobs;

implementation

uses System.Classes, cocinasync.async, System.Diagnostics;

type
  TJobs = class;

  TJobRunner = class(TThread)
  strict private
    [Weak]
    FJobs : TJobs;
    FName : string;
  protected
    procedure Execute; override;
  public
    constructor Create(Jobs : TJobs; JobNumber : integer); reintroduce; virtual;
  end;

  TJobs = class(TInterfacedObject, IJobs)
  strict private
    FTerminating : boolean;
    FRunners : TQueue<TJobRunner>;
    FJobs : TQueue<IJob>;
    FName : string;
    procedure TerminateRunners;
  private
    FJobRunnerCount : integer;
    FJobsInProcess : integer;
  public
    constructor Create(RunnerCount : Integer; MaxJobs : Integer = 4096; const AName : string = ''); reintroduce; virtual;
    destructor Destroy; override;

    function Next : IJob; inline;
    function Name : string;
    function Queue(const DoIt : TProc) : IJob; overload; inline;
    function Queue(const Job : IJob) : IJob; overload; inline;
    procedure WaitForAll(Timeout : Cardinal = INFINITE); inline;
    property Terminating : boolean read FTerminating;
  end;

{ TJobManager }

class function TJobManager.CreateJobs(RunnerCount : Cardinal = 0; MaxJobs : Integer = 4096; const Name : string = '') : IJobs;
var
  iCnt : Cardinal;
begin
  if RunnerCount = 0 then
    iCnt := CPUCount*4  // default to 4 threads per native/hyperthreaded processing unit.
  else
    iCnt := RunnerCount;

  if iCnt < 6 then
    iCnt := 6;

  Result := TJobs.Create(iCnt, MaxJobs, Name);
end;

class function TJobManager.Execute(const AJob: TProc; AJobs : IJobs = nil; const AName : string = ''): IJob;
begin
  Result := Job(AJob);
  if AJobs = nil then
    AJobs := Jobs;
  AJobs.Queue(Result);
end;

class function TJobManager.Execute<T>(const AJob: TFunc<T>; AJobs : IJobs = nil; const AName : string = ''): IJob<T>;
begin
  Result := Job<T>(AJob);
  if AJobs = nil then
    AJobs := Jobs;
  AJobs.Queue(Result);
end;

class function TJobManager.Execute(const AJob: TProc; AQueue: TJobQueue; AJobs : IJobs = nil; const AName : string = ''): IJob;
begin
  Result := Job(AJob);
  AQueue.Enqueue(Result);
  if AJobs = nil then
    AJobs := Jobs;
  Jobs.Queue(Result);
end;

class function TJobManager.Execute<T>(const AJob: TFunc<T>; AQueue: TJobQueue<T>; AJobs : IJobs = nil; const AName : string = ''): IJob<T>;
begin
  Result := Job<T>(AJob);
  AQueue.Enqueue(Result);
  if AJobs = nil then
    AJobs := Jobs;
  AJobs.Queue(Result);
end;

class procedure TJobManager.HideMonitor;
begin
  if Assigned(FMonitor) then
    FMonitor.OnHideMonitor();
end;

class function TJobManager.Job(const AJob: TProc; const AName : string = ''): IJob;
begin
  Result := TDefaultJob<Boolean>.Create(AJob,nil, AName);
end;

class function TJobManager.Job<T>(const AJob: TFunc<T>; const AName : string = ''): IJob<T>;
begin
  Result := TDefaultJob<T>.Create(nil, AJob, AName);
end;

class procedure TJobManager.RegisterMonitor(Monitor: IJobMonitor);
begin
  FMonitor := Monitor;
end;

class procedure TJobManager.ShowMonitor;
begin
  if Assigned(FMonitor) then
    FMonitor.OnShowMonitor;
end;

class procedure TJobManager.UnregisterMonitor(Monitor: IJobMonitor);
begin
  TInterlocked.CompareExchange(Pointer(FMonitor), nil, Pointer(Monitor));
end;

{ TJobs }

constructor TJobs.Create(RunnerCount: Integer; MaxJobs : Integer = 4096; const AName : string = '');
begin
  inherited Create;
  if AName = '' then
    FName := Classname+'($'+IntToHex(Integer(@Self),SizeOf(Pointer))+')'
  else
    FName := AName;
  FTerminating := False;
  FJobs := TQueue<IJob>.Create(MaxJobs);
  FJobRunnerCount := 0;
  FJobsInProcess := 0;
  FRunners := TQueue<TJobRunner>.Create(RunnerCount+1);
  while FRunners.Count < RunnerCount do
    FRunners.Enqueue(TJobRunner.Create(Self,FRunners.Count+1));
end;

destructor TJobs.Destroy;
begin
  TerminateRunners;
  FJobs.Free;
  FRunners.Free;
  inherited;
end;

function TJobs.Name: string;
begin
  Result := FName;
end;

function TJobs.Next: IJob;
begin
  Result := FJobs.Dequeue;
end;

function TJobs.Queue(const DoIt: TProc) : IJob;
begin
  Result := Queue(TJobManager.Job(DoIt));
end;

function TJobs.Queue(const Job : IJob) : IJob;
begin
  if FTerminating then
    raise Exception.Create('Cannot queue while Jobs are terminating.');
  Result := Job;
  FJobs.Enqueue(Job);
end;

procedure TJobs.TerminateRunners;
var
  r : TJobRunner;
  rq : TQueue<TJobRunner>;
begin
  FTerminating := True;
  WaitForAll(3000);
  FJobs.Clear;

  rq := TQueue<TJobRunner>.Create(FRunners.Count+1);
  try
    repeat
      r := FRunners.Dequeue;
      if not Assigned(r) then
        break;
      r.Terminate;
      rq.Enqueue(r);
    until not Assigned(r);

    while FJobRunnerCount > 0 do
      Sleep(10);

    repeat
      r := rq.Dequeue;
      r.Free;
    until not Assigned(r);
  finally
    rq.Free;
  end;
end;


procedure TJobs.WaitForAll(Timeout : Cardinal = INFINITE);
var
  timer : TStopWatch;
  sw : TSpinWait;
begin
  timer := TStopWatch.StartNew;
  sw.Reset;
  while ((FJobs.Count > 0) or (FJobsInProcess > 0)) and
        (  (Timeout = 0) or
           ((Timeout > 0) and (timer.ElapsedMilliseconds <= Timeout))
        ) do
    sw.SpinCycle;
end;

{ TJobRunner }

constructor TJobRunner.Create(Jobs : TJobs; JobNumber : integer);
begin
  inherited Create(False);
  FJobs := Jobs;
  FName := FJobs.Name+'.'+JobNumber.ToString;
  FreeOnTerminate := False;
end;

procedure TJobRunner.Execute;
var
  wait : TSpinWait;
  job : IJob;
begin
  TInterlocked.Increment(FJobs.FJobRunnerCount);
  try
    wait.Reset;
    while not Terminated do
    begin
      job := FJobs.Next;
      if job <> nil then
      begin
        if FJobs.Terminating then
          exit;

        TInterlocked.Increment(FJobs.FJobsInProcess);
        try
          if Assigned(TJobManager.FMonitor) then
            TJobManager.FMonitor.OnBeginJob(FName, job.Name);
          try
            wait.Reset;
            job.SetupJob;
            try
              job.ExecuteJob;
            finally
              job.FinishJob;
            end;
          finally
            if Assigned(TJobManager.FMonitor) then
              TJobManager.FMonitor.OnEndJob(FName, job.Name);
          end;
        finally
          TInterlocked.Decrement(FJobs.FJobsInProcess);
        end;
      end else
        wait.SpinCycle;
    end;
  finally
    TInterlocked.Decrement(FJobs.FJobRunnerCount);
  end;
end;

{ TDefaultJob }

constructor TDefaultJob<T>.Create(ProcToExecute : TProc; FuncToExecute : TFunc<T>; AName : string);
begin
  inherited Create;
  FExecutionTime := 0;
  if AName = '' then
    FName := ClassName+'($'+IntToHex(Integer(@Self),SizeOf(Pointer))+')'
  else
    FName := AName;
  FException := TJobException.Init;
  FResult := T(nil);
  FProcToExecute := ProcToExecute;
  FFuncToExecute := FuncToExecute;
  FEvent := TEvent.Create;
  FEvent.ResetEvent;
end;

destructor TDefaultJob<T>.Destroy;
begin
  FEvent.Free;
  inherited;
end;

procedure TDefaultJob<T>.ExecuteJob;
var
  sw : TStopWatch;
begin
  if not FException.Triggered then
    try
      sw := TStopWatch.Create;
      try
        sw.Start;
        if Assigned(FProcToExecute) then
          FProcToExecute()
        else if Assigned(FFuncToExecute) then
          FResult := FFuncToExecute();
      finally
        FExecutionTime := sw.ElapsedMilliseconds;
      end;
    except
      on e: Exception do
      begin
        FException.Update(e);
      end;
    end;
  SetEvent;
end;

function TDefaultJob<T>.ExecutionTime: Cardinal;
begin
  Result := FExecutionTime;
end;

procedure TDefaultJob<T>.FinishJob;
begin
  // Nothing to finish
end;

function TDefaultJob<T>.Name: string;
begin
  Result := FName;
end;

procedure TDefaultJob<T>.RaiseExceptionIfExists;
begin
  FException.RaiseExceptionIfExists;
end;

function TDefaultJob<T>.Result: T;
begin
  Wait;
  RaiseExceptionIfExists;
  Result := FResult;
end;

procedure TDefaultJob<T>.SetEvent;
begin
  FEvent.SetEvent;
end;

procedure TDefaultJob<T>.SetupJob;
begin
  // Nothing to Setup
end;

procedure TDefaultJob<T>.Wait(var Completed: boolean; Timeout: Cardinal = INFINITE);
var
  wr : TWaitResult;
begin
  wr := FEvent.WaitFor(Timeout);
  Completed := wr <> TWaitResult.wrTimeout;
  RaiseExceptionIfExists;
end;

function TDefaultJob<T>.Wait(Timeout: Cardinal = INFINITE): boolean;
var
  wr : TWaitResult;
begin
  wr := FEvent.WaitFor(Timeout);
  Result := wr <> TWaitResult.wrTimeout;
  RaiseExceptionIfExists;
end;


{ TJobQueue }

procedure TJobQueue.Abort;
var
  j : IJob;
begin
  repeat
    j := Dequeue;
  until j = nil;
end;

function TJobQueue.WaitForAll(Timeout: Cardinal = INFINITE): boolean;
var
  j : IJob;
  timer : TStopWatch;
begin
  timer := TStopWatch.StartNew;
  Result := True;
  while Count > 0 do
  begin
    j := Dequeue;
    if not j.Wait(1) then
      Enqueue(j);
    if (Count > 0) and (timer.ElapsedMilliseconds >= Timeout) then
    begin
      Result := False;
      break;
    end;
  end;
end;

{ TJobQueue<T> }

procedure TJobQueue<T>.Abort;
var
  j : IJob;
begin
  repeat
    j := Dequeue;
  until j = nil;
end;

function TJobQueue<T>.WaitForAll(Timeout: Cardinal = INFINITE): boolean;
var
  j : IJob<T>;
  timer : TStopWatch;
begin
  timer := TStopWatch.StartNew;
  Result := True;
  while Count > 0 do
  begin
    j := Dequeue;
    if not j.Wait(1) then
      Enqueue(j);
    if (Count > 0) and (timer.ElapsedMilliseconds >= Timeout) then
    begin
      Result := False;
      break;
    end;
  end;
end;

{ TJobException }

class function TJobException.Init: TJobException;
begin
  Result.Clss := '';
  Result.Msg := '';
  Result.Triggered := False;
end;

procedure TJobException.RaiseExceptionIfExists;
begin
  if Self.Triggered then
    raise EJobExecutionFailure.Create('Job Exception raised "'+Self.Clss+': '+Self.Msg+'"');
end;

procedure TJobException.Update(E: Exception);
begin
  if Assigned(E) then
  begin
    Self.Clss := E.ClassName;
    Self.Msg := E.Message;
    Self.Triggered := True;
  end;
end;

initialization
  Jobs := TJobManager.CreateJobs(0,4096,'Default');

finalization
  Jobs.WaitForAll;

end.
