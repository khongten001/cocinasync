unit cocinasync.monitor.fmx;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.TreeView,
  FMX.Layouts, FMX.ListBox, FMX.StdCtrls, FMX.Controls.Presentation,
  cocinasync.monitor;

type
  Tcocinasync_fmx_monitor = class(TForm, IJobMonitor)
    Panel1: TPanel;
    Panel2: TPanel;
    Splitter1: TSplitter;
    Panel3: TPanel;
    Panel4: TPanel;
    lbQueue: TListBox;
    tvRunners: TTreeView;
    Label1: TLabel;
    Label2: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
  public
    procedure OnBeginJob(const Runner: string; const ID: string);
    procedure OnDequeueJob(const ID: string);
    procedure OnEndJob(const Runner: string; const ID: string);
    procedure OnEnqueueJob(const ID: string);
    procedure OnHideMonitor;
    procedure OnShowMonitor;
  end;

implementation

uses cocinasync.async, cocinasync.jobs;

{$R *.fmx}

{ Tcocinasync_fmx_monitor }

procedure Tcocinasync_fmx_monitor.FormCreate(Sender: TObject);
begin
  Name := '';
  TJobManager.RegisterMonitor(Self);
end;

procedure Tcocinasync_fmx_monitor.FormDestroy(Sender: TObject);
begin
   TJobManager.UnregisterMonitor(Self);
end;

procedure Tcocinasync_fmx_monitor.OnBeginJob(const Runner, ID: string);
begin
  TAsync.QueueIfInThread(
    procedure
    var
      tn, ti : TTreeViewItem;
    begin
      tvRunners.BeginUpdate;
      try
        tn := tvRunners.ItemByText(Runner);
        if tn = nil then
        begin
          tn := TTreeViewItem.Create(tvRunners);
          tn.Text := Runner;
          tvRunners.AddObject(tn);
        end;
        ti := TTreeViewItem.Create(tn);
        ti.Text := ID;
        tn.AddObject(ti);
        tn.Expand;
      finally
        tvRunners.EndUpdate;
      end;
    end
  );
end;

procedure Tcocinasync_fmx_monitor.OnDequeueJob(const ID: string);
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

procedure Tcocinasync_fmx_monitor.OnEndJob(const Runner, ID: string);
begin
  TAsync.QueueIfInThread(
    procedure
    var
      i: Integer;
      tn : TTreeViewItem;
    begin
      tvRunners.BeginUpdate;
      try
        tn := tvRunners.ItemByText(Runner);
        if tn = nil then
        begin
          tn := TTreeViewItem.Create(tvRunners);
          tn.Text := Runner;
          tvRunners.AddObject(tn);
        end;
        for i := 0 to tn.Count-1 do
          if tn.Items[i].Text = ID then
          begin
            tn.Items[i].Free;
            break;
          end;
      finally
        tvRunners.EndUpdate;
      end;
    end
  );
end;

procedure Tcocinasync_fmx_monitor.OnEnqueueJob(const ID: string);
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

procedure Tcocinasync_fmx_monitor.OnHideMonitor;
begin
  self.Hide;
end;

procedure Tcocinasync_fmx_monitor.OnShowMonitor;
begin
  self.Show;
end;

initialization
  Async.AfterDo(1000,
    procedure
    begin
      Tcocinasync_fmx_monitor.Create(Application);
    end
  );

end.
