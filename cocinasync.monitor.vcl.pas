unit cocinasync.monitor.vcl;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, cocinasync.monitor,
  Vcl.ComCtrls;

type
  Tcocinasync_vcl_monitor = class(TForm, IJobMonitor)
    Splitter1: TSplitter;
    Panel2: TPanel;
    lbQueue: TListBox;
    Panel1: TPanel;
    Label1: TLabel;
    Panel3: TPanel;
    Panel4: TPanel;
    Label2: TLabel;
    tvRunners: TTreeView;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
  public
    procedure OnBeginJob(const Runner: string; const ID: string);
    procedure OnDequeueJob(const ID: string);
    procedure OnEndJob(const Runner : string; const ID: string);
    procedure OnEnqueueJob(const ID: string);
    procedure OnHideMonitor;
    procedure OnShowMonitor;
  end;

implementation

uses cocinasync.jobs, cocinasync.async;

{$R *.dfm}

{ Tcocinasync_vcl_monitor }

procedure Tcocinasync_vcl_monitor.FormCreate(Sender: TObject);
begin
  Name := '';
  TJobManager.RegisterMonitor(Self);
end;

procedure Tcocinasync_vcl_monitor.FormDestroy(Sender: TObject);
begin
  TJobManager.UnregisterMonnitor(Self);
end;

procedure Tcocinasync_vcl_monitor.OnBeginJob(const Runner: String; const ID: string);
begin
  TAsync.QueueIfInThread(
    procedure
    var
      i: Integer;
      tn : TTreeNode;
    begin
      tvRunners.Items.BeginUpdate;
      try
        tn := nil;
        for i := 0 to tvRunners.Items.Count-1 do
          if tvRunners.Items[0].Text = Runner then
          begin
            tn := tvRunners.Items[0];
            break;
          end;
        if tn = nil then
          tn := tvRunners.Items.AddChild(nil,Runner);
        tvRunners.Items.AddChild(tn,ID);
        tn.Expand(True);
      finally
        tvRunners.Items.EndUpdate;
      end;
    end
  );
end;

procedure Tcocinasync_vcl_monitor.OnDequeueJob(const ID: string);
begin
  TAsync.QueueIfInThread(
    procedure
    var
      idx : integer;
    begin
      lbQueue.Items.BeginUpdate;
      try
        idx := lbQueue.Items.IndexOf(ID);
        if idx >= 0 then
          lbQueue.Items.Delete(idx);
      finally
        lbQueue.Items.EndUpdate;
      end;
    end
  );
end;

procedure Tcocinasync_vcl_monitor.OnEndJob(const Runner: string; const ID: string);
begin
  TAsync.QueueIfInThread(
    procedure
    var
      i: Integer;
      tn : TTreeNode;
    begin
      tvRunners.Items.BeginUpdate;
      try
        tn := nil;
        for i := 0 to tvRunners.Items.Count-1 do
          if tvRunners.Items[0].Text = Runner then
          begin
            tn := tvRunners.Items[0];
            break;
          end;
        if tn = nil then
          tn := tvRunners.Items.AddChild(nil,Runner);
        for i := 0 to tn.Count-1 do
          if tn.Item[i].Text = ID then
          begin
            tn.Item[i].Delete;
            break;
          end;
      finally
        tvRunners.Items.EndUpdate;
      end;
    end
  );
end;

procedure Tcocinasync_vcl_monitor.OnEnqueueJob(const ID: string);
begin
  TAsync.QueueIfInThread(
    procedure
    begin
      lbQueue.Items.BeginUpdate;
      try
        lbQueue.Items.Add(ID);
      finally
        lbQueue.Items.EndUpdate;
      end;
    end
  );
end;

procedure Tcocinasync_vcl_monitor.OnHideMonitor;
begin
  self.Hide;
end;

procedure Tcocinasync_vcl_monitor.OnShowMonitor;
begin
  self.Show;
end;

initialization
  Async.AfterDo(1000,
    procedure
    begin
      Tcocinasync_vcl_monitor.Create(Application);
    end
  );

end.
