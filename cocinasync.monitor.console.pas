unit cocinasync.monitor.console;

interface

uses cocinasync.monitor;

implementation

uses System.SysUtils, System.Classes, cocinasync.jobs;

type
  TConsoleMonitor = class(TInterfacedObject, IJobMonitor)
  private
    FEnabled : boolean;
  public
    procedure OnBeginJob(const Runner: string; const ID: string);
    procedure OnDequeueJob(const ID: string);
    procedure OnEndJob(const Runner: string; const ID: string);
    procedure OnEnqueueJob(const ID: string);
    procedure OnHideMonitor;
    procedure OnShowMonitor;

    constructor Create; reintroduce;
    destructor Destroy; override;
  end;

var
  cm : TConsoleMonitor;

{ TConsoleMonitor }

constructor TConsoleMonitor.Create;
begin
  inherited Create;
  FEnabled := False;
  TJobManager.RegisterMonitor(Self);
end;

destructor TConsoleMonitor.Destroy;
begin
  TJobManager.UnregisterMonnitor(Self);
  inherited;
end;

procedure TConsoleMonitor.OnBeginJob(const Runner, ID: string);
begin
  if FEnabled then
    WriteLn(Runner+' Started '+ID);
end;

procedure TConsoleMonitor.OnDequeueJob(const ID: string);
begin
  if FEnabled then
    WriteLn('Dequeued '+ID);
end;

procedure TConsoleMonitor.OnEndJob(const Runner, ID: string);
begin
  if FEnabled then
    WriteLn(Runner+' Finished '+ID);
end;

procedure TConsoleMonitor.OnEnqueueJob(const ID: string);
begin
  if FEnabled then
    WriteLn('Enqueued '+ID);
end;

procedure TConsoleMonitor.OnHideMonitor;
begin
  FEnabled := False;
end;

procedure TConsoleMonitor.OnShowMonitor;
begin
  FEnabled := True;
end;

initialization
  cm := TConsoleMonitor.Create;

finalization
  cm.Free;

end.
