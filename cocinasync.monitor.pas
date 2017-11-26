unit cocinasync.monitor;

interface

uses System.SysUtils, System.Classes;

type
  TJobIDHandler = reference to procedure(const ID : string);
  TJobProcessingHandler = reference to procedure(Runner : Integer; const ID : string);

  IJobMonitor = interface(IInterface)
    procedure OnEnqueueJob(const ID : string);
    procedure OnDequeueJob(const ID : string);
    procedure OnBeginJob(const Runner : string; const ID : string);
    procedure OnEndJob(const Runner : string; const ID : string);
    procedure OnShowMonitor;
    procedure OnHideMonitor;
  end;

implementation

end.
