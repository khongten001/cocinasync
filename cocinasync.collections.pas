unit cocinasync.collections;

interface

uses System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Defaults,
  System.TypInfo;

resourcestring
  S_ARRAYISFULL = 'The queue is full';
  S_ARRAYISEMPTY = 'The queue is empty';

type
  EQueueSizeException = class(Exception)
  end;

  EKeyExists<K> = class(Exception)
  public
    constructor Create(Key : K); reintroduce; virtual;
  end;

  TQueue<T> = class(TObject)
  strict private
    FData : System.TArray<T>;
    FSize : integer;
    FWriteIndex : integer;
    FReadIndex : integer;
    FReadIndexMax : integer;
    function IndexOf(idx : integer) : integer; inline;
    function GetItems(idx: integer): T;  inline;
    function GetCount: integer;  inline;
  public
    constructor Create(Size : Integer); reintroduce; overload; virtual;
    constructor Create(&Array : TArray<T>); reintroduce; overload; virtual;
    constructor Create(&ArrayPtr : Pointer); reintroduce; overload; virtual;
    destructor Destroy; override;

    procedure Enqueue(Value : T); inline;
    function Dequeue : T; inline;
    procedure Clear; inline;

    property Items[idx : integer] : T read GetItems; default;
    property Count : integer read GetCount;
    property Size : integer read FSize;
    procedure WithDo(AJob : TProc<T>; WaitForItems : boolean = false; AOnWait : TProc<boolean> = nil);
  end;

  TStack<T> = class(TObject)
  strict private type
    PStackPointer = ^TStackPointer;
    TStackPointer = record
      FData : T;
      FPrior : Pointer;
    end;
  strict private
    FTop : Pointer;
    FDisposeQueue : TQueue<PStackPointer>;
  public
    constructor Create; reintroduce; virtual;
    destructor Destroy; override;

    procedure Push(const Value: T); inline;
    function Pop: T; overload; inline;
    procedure Clear; inline;
  end;

  TVisitorProc<K,V> = reference to procedure(const Key : K; var Value : V; var Delete : Boolean);
  TValueProc<K,V> = reference to procedure(const Key : K; var Value : V);

  THash<K,V> = class(TObject)
  private
    type
    PValue = ^V;
    PItem = ^TItem;
    TItem = record
      Key: K;
      Value: V;
      Next: Pointer;
      Visiting : integer;
      Removed : integer;
    end;
    TItemArray = system.TArray<Pointer>;
    PItemArray = ^TItemArray;
  strict private
    FMemSize: Cardinal;
    FItems: PItemArray;
    FComparer : IEqualityComparer<K>;
    FKeyType: PTypeInfo;
    procedure GetMapPointer(Key: K; HashIdx : integer; var Prior, Current : PItem; var Depth : Integer); inline;
    function GetMap(Key: K): V;  inline;
    procedure SetMap(Key: K; const Value: V; NewItem : PItem; const wait : TSpinWait; AllowOverwrite : boolean); overload; inline;
    procedure SetMap(Key: K; const Value: V; AllowOverwrite : boolean); overload;  inline;
    procedure SetMap(Key: K; const Value: V); overload;  inline;
    function GetHas(Key: K): boolean; inline;
    function GetHashIndex(Key : K) : Integer; inline;
    function CalcDepth(item: PItem): integer; inline;
    function Remove(const Key : K; const wait : TSpinWait) : V; overload; inline;
    function SwapItemsArray(NewItems : PItemArray) : PItemArray;
    procedure DisposeOfItems(pi: PItemArray);
  public
    type
      TDepth = record
        EmptyCnt : Cardinal;
        MaxDepth : Cardinal;
        Average  : Cardinal;
        AvgFilled : Cardinal;
        Size : Cardinal;
      end;
  public
    constructor Create(EstimatedItemCount : Cardinal = 1024); reintroduce; virtual;
    destructor Destroy; override;

    function DebugDepth : TDepth;
    function Remove(const Key : K) : V; overload; inline;
    procedure AddOrSetValue(const Key : K; const Value : V);  inline;
    procedure Add(const Key : K; const Value : V);  inline;
    property Has[Key : K] : boolean read GetHas;
    property Map[Key : K] : V read GetMap write SetMap; default;
    procedure Visit(const visitor : TVisitorProc<K,V>);
    procedure Clear(OnFree : TValueProc<K,V> = nil);
  end;

  TInterlockedHelper = class helper for TInterlocked
  public
    class function CompareExchange(var Target: Pointer; Value: Pointer; Comparand: Pointer; out Succeeded: Boolean): Pointer; overload;
    class function CompareExchange<K,V>(var Target: THash<K,V>.PItemArray; Value: THash<K,V>.PItemArray; Comparand: THash<K,V>.PItemArray; out Succeeded: Boolean): Pointer; overload;
    class function CompareExchange(var Target: UInt64; Value: UInt64; Comparand: UInt64; out Succeeded: Boolean): UInt64; overload;
    class function Exchange<T>(var Target: T; Value: T): T; overload;
  end;

implementation

uses Math, System.Generics.Collections, cocinasync.jobs;

{ TInterlockedHelper }

class function TInterlockedHelper.CompareExchange(var Target: Pointer; Value: Pointer; Comparand: Pointer; out Succeeded: Boolean): Pointer;
begin
  Result := AtomicCmpExchange(Target, Value, Comparand, Succeeded);
end;

class function TInterlockedHelper.CompareExchange(var Target: UInt64; Value,
  Comparand: UInt64; out Succeeded: Boolean): UInt64;
begin
  Result := AtomicCmpExchange(Target, Value, Comparand, Succeeded);
end;


class function TInterlockedHelper.CompareExchange<K, V>(
  var Target: THash<K, V>.PItemArray; Value, Comparand: THash<K, V>.PItemArray;
  out Succeeded: Boolean): Pointer;
begin
  Result := AtomicCmpExchange(Target, Value, Comparand, Succeeded);
end;

class function TInterlockedHelper.Exchange<T>(var Target: T; Value : T): T;
begin
  TObject((@Result)^) := Exchange(TObject((@Target)^), TObject((@Value)^));
end;

{ TQueue<T> }

procedure TQueue<T>.Clear;
begin
  repeat
    Dequeue;
  until IndexOf(FReadIndex) = IndexOf(FReadIndexMax);
end;

constructor TQueue<T>.Create(Size: Integer);
begin
  inherited Create;
  FSize := Size;
  SetLength(FData, Size);
end;

constructor TQueue<T>.Create(&Array: TArray<T>);
var
  i: Integer;
begin
  Create(Length(&Array)+1);
  for i := low(&Array) to high(&Array) do
    Enqueue(&Array[i]);
end;

constructor TQueue<T>.Create(ArrayPtr: Pointer);
var
  i: Integer;
begin
  Create(TArray<T>(ArrayPtr^));
end;

function TQueue<T>.Dequeue: T;
var
  iMaxRead, iRead : integer;
  bSuccess : boolean;
  sw : TSpinWait;
  p : pointer;
begin
  sw.Reset;
  repeat
    iRead := FReadIndex;
    iMaxRead := FReadIndexMax;

    if IndexOf(iRead) = IndexOf(iMaxRead) then
      exit(T(nil));

    Result := FData[IndexOf(iRead)];

    TInterlocked.CompareExchange(FReadIndex, iRead+1, iRead, bSuccess);
    if not bSuccess then
      sw.SpinCycle;
  until bSuccess;

  if IsManagedType(T) then
  begin
    p := @FData[IndexOf(iRead)];
    TInterlocked.CompareExchange(p,nil,@Result);
  end;
end;

destructor TQueue<T>.Destroy;
begin
  Clear;
  inherited;
end;

procedure TQueue<T>.Enqueue(Value: T);
var
  bSuccess : boolean;
  iRead, iWrite : integer;
  sw : TSpinWait;
begin
  sw.Reset;
  repeat
    iWrite := FWriteIndex;
    iRead := FReadIndex;
    if IndexOf(iWrite + 1) = IndexOf(iRead) then
      raise EQueueSizeException.Create(S_ARRAYISFULL);
    TInterlocked.CompareExchange(FWriteIndex, iWrite+1, iWrite, bSuccess);
    if not bSuccess then
      sw.SpinCycle;
  until bSuccess;

  FData[IndexOf(iWrite)] := Value;

  sw.Reset;
  repeat
    TInterlocked.CompareExchange(FReadIndexMax, iWrite+1, iWrite, bSuccess);
    if not bSuccess then
      sw.SpinCycle;
  until (bSuccess);
end;

function TQueue<T>.GetItems(idx: integer): T;
begin
  Result := FData[IndexOf(idx)];
end;

function TQueue<T>.GetCount : integer;
begin
  Result := FReadIndexMax - FReadIndex;
end;

function TQueue<T>.IndexOf(idx: integer): integer;
begin
  result := idx mod FSize;
end;

procedure TQueue<T>.WithDo(AJob: TProc<T>; WaitForItems: boolean;
  AOnWait: TProc<boolean>);
begin
  TJobManager.ProcessQueue<T>(Self, AJob, WaitForItems, AOnWait);
end;

{ TStack<T> }

procedure TStack<T>.Clear;
begin
  while FTop <> nil do
    Pop;
end;

constructor TStack<T>.Create;
begin
  inherited Create;
  FTop := nil;
  FDisposeQueue := TQueue<PStackPointer>.Create(256);
end;

destructor TStack<T>.Destroy;
var
  p : PStackPointer;
begin
  Clear;
  repeat
    p := FDisposeQueue.Dequeue;
    if p <> nil then
      Dispose(p);
  until p = nil;
  FDisposeQueue.Free;
  inherited;
end;

function TStack<T>.Pop: T;
var
  p : PStackPointer;
  bSuccess : boolean;
  wait : TSpinWait;
begin
  wait.Reset;

  if FTop = nil then
    exit(T(nil));

  repeat
    p := FTop;
    if p <> nil then
      TInterlocked.CompareExchange(FTop,p^.FPrior, p, bSuccess)
    else
      exit(T(nil));
    if not bSuccess then
      wait.SpinCycle;
  until bSuccess;

  Result := p^.FData;

  FDisposeQueue.Enqueue(p);
  if FDisposeQueue.Count > 192 then
  begin
    while FDisposeQueue.Count > 128 do
    begin
      p := FDisposeQueue.Dequeue;
      if p <> nil then
        Dispose(p);
    end;
  end;
end;

procedure TStack<T>.Push(const Value: T);
var
  pNew : PStackPointer;
  wait : TSpinWait;
  bSuccess : boolean;
begin
  wait.Reset;
  if FDisposeQueue.Count > 64 then
    pNew := FDisposeQueue.Dequeue
  else
    New(pNew);
  pNew^.FData := Value;
  repeat
    pNew^.FPrior := FTop;
    TInterlocked.CompareExchange(FTop,pNew, pNew^.FPrior,bSuccess);
    if not bSuccess then
    begin
      wait.SpinCycle;
    end;
  until bSuccess;
end;



{ THash<K, V> }

procedure THash<K, V>.Add(const Key: K; const Value: V);
begin
  SetMap(Key, Value, False);
end;

procedure THash<K, V>.AddOrSetValue(const Key: K; const Value: V);
begin
  SetMap(Key, Value, True);
end;

constructor THash<K, V>.Create(EstimatedItemCount : Cardinal = 1024);
var
  i: Integer;
  pi : PItemArray;
begin
  inherited Create;
  FMemSize := $FFFFFF;
  while (EstimatedItemCount < FMemSize) and (FMemSize > $F) do
    FMemSize := FMemSize shr 4;

  New(pi);
  SwapItemsArray(pi);
  SetLength(FItems^,FMemSize+1);
  FKeyType := TypeInfo(K);
  FComparer := TEqualityComparer<K>.Default;
  for i := Low(FItems^) to High(FItems^) do
    FItems^[i] := nil;
end;

function THash<K, V>.CalcDepth(item : PItem) : integer;
begin
  Result := 1;
  while (item <> nil) and (item^.Next <> nil) do
  begin
    inc(Result);
    item := item^.Next;
  end;
end;

procedure THash<K, V>.Clear(OnFree: TValueProc<K, V> = nil);
var
  pi : PItemArray;
  i : integer;
  p : PItem;
begin
  New(pi);
  pi := SwapItemsArray(pi);
  try
    if Assigned(OnFree) then
      for i := low(pi^) to High(pi^) do
      begin
        p := FItems^[i];
        if p <> nil then
        begin
          repeat
            TInterlocked.Increment(p^.Visiting);
            try
              OnFree(p^.Key, p^.Value);
            finally
              TInterlocked.Decrement(p^.Visiting);
            end;
            p := p^.Next;
          until p = nil
        end;
      end;
  finally
    DisposeOfItems(pi);
  end;
end;


procedure THash<K, V>.DisposeOfItems(pi: PItemArray);
var
  pNext: PItem;
  Local_i: Integer;
  i: Integer;
  p: PItem;
begin
  for i := Low(pi^) to High(pi^) do
    if pi^[i] <> nil then
    begin
      p := PItem(PItem(pi^[i])^.Next);
      while p <> nil do
      begin
        pNext := p^.Next;
        p^.Value := V(nil);
        Dispose(PItem(p));
        p := pNext;
      end;
      Dispose(PItem(pi^[i]));
    end;
  Dispose(pi);
end;

function THash<K, V>.DebugDepth: TDepth;
var
  i, iDepth : integer;
begin
  Result.EmptyCnt := 0;
  Result.MaxDepth := 0;
  Result.Average := 0;
  Result.AvgFilled := 0;
  Result.Size := FMemSize+1;
  for i := 0 to FMemSize do
  begin
    if FItems^[i] <> nil then
    begin
      iDepth := CalcDepth(FItems^[I]);
      Result.MaxDepth := Max(Result.MaxDepth, iDepth);
      inc(Result.Average,iDepth);
      inc(Result.AvgFilled, iDepth);
    end else
      Inc(Result.EmptyCnt);
  end;
  Result.Average := Result.Average div (FMemSize+1);
  if FMemSize >= Result.EmptyCnt then
    Result.AvgFilled := Result.AvgFilled div ((FMemSize+1) - Result.EmptyCnt)
  else
    Result.AvgFilled := Result.Average;
end;

function THash<K, V>.Remove(const Key: K; const wait: TSpinWait) : V;
var
  p, pPrior : PItem;
  iDepth : integer;
  bSuccess : boolean;
begin
  GetMapPointer(Key, GetHashIndex(Key), pPrior, p, iDepth);
  if p <> nil then
  begin
    if pPrior = nil then
      TInterlocked.CompareExchange(FItems^[GetHashIndex(Key)],p^.Next, p, bSuccess)
    else
      TInterlocked.CompareExchange(pPrior^.Next, p^.Next, p, bSuccess);

    if not bSuccess then
    begin
      wait.SpinCycle;
      Result := Remove(Key, wait);
    end else
    begin
      Result := p^.Value;
      Dispose(p);
    end;
  end else
    Result := V(nil);
end;

function THash<K, V>.Remove(const Key: K) : V;
var
  sw : TSpinWait;
begin
  sw.Reset;
  Result := Remove(Key, sw);
end;

destructor THash<K, V>.Destroy;
var
  p, pNext : PItem;
  i: Integer;
begin
  DisposeOfItems(FItems);
  inherited;
end;

function THash<K, V>.GetHas(Key: K): boolean;
var
  p, pPrior: PItem;
  iDepth: integer;
begin
  GetMapPointer(Key, GetHashIndex(Key), pPrior, p, iDepth);
  Result := (p <> nil) and (p^.Removed = 0);
end;

function THash<K, V>.GetHashIndex(Key: K): Integer;
  const Mask = not Integer($80000000);
begin
  result := (Mask and ((Mask and FComparer.GetHashCode(Key)) + 1)) and (FMemSize);
end;

function THash<K, V>.GetMap(Key: K): V;
var
  p, pPrior : PItem;
  iDepth : integer;
begin
  GetMapPointer(Key, GetHashIndex(Key), pPrior, p, iDepth);
  if p <> nil then
  begin
    TInterlocked.Increment(p^.Visiting);
    try
      if p^.Removed = 0 then
        Result := p^.Value
      else
        Result := V(nil);
    finally
      TInterlocked.Decrement(p^.Visiting);
    end;
  end else
    Result := V(nil);
end;

procedure THash<K, V>.GetMapPointer(Key: K; HashIdx : integer; var Prior, Current : PItem; var Depth : Integer);
var
  p : PItem;
begin
  Depth := 0;
  Prior := nil;
  p := FItems^[HashIdx];
  if p <> nil then
  begin
    if not FComparer.Equals(p.Key, Key) then
    begin
      repeat
        Prior := p;
        p := p^.Next;
        inc(Depth);
      until (p = nil) or FComparer.Equals(p.Key, Key);

      if p <> nil then
        Current := p
      else
        Current := nil;
    end else
      Current := p;
  end else
    Current := nil;
end;

procedure THash<K, V>.SetMap(Key: K; const Value: V; NewItem: PItem; const wait : TSpinWait; AllowOverwrite : boolean);
var
  p, pNew, pDisp, pPrior : PItem;
  iDepth, idx : Integer;
  bSuccess : boolean;
  vValue : V;
begin
  idx := GetHashIndex(Key);
  pPrior := nil;
  GetMapPointer(Key, idx, pPrior, p, iDepth);

  if p = nil then
  begin
    if NewItem = nil then
    begin
      New(pNew);
      pNew^.Key := Key;
      pNew^.Value := Value;
      pNew^.Visiting := 0;
      pNew^.Removed := 0;
    end else
      pNew := NewItem;
    pNew^.Next := nil;

    if iDepth > 0 then
    begin
      // Slot occupied but key not found
      pNew^.Next := p;
      TInterlocked.CompareExchange(pPrior^.Next, pNew, p, bSuccess);
      if not bSuccess then
      begin
        wait.SpinCycle;
        SetMap(Key,Value, pNew, wait, AllowOverwrite);
      end;
    end else
    begin
      // Slot open, start linked list with key
      TInterlocked.CompareExchange(FItems^[idx],pNew,p,bSuccess);
      if not bSuccess then
      begin
        wait.SpinCycle;
        SetMap(Key,Value, pNew, wait, AllowOverwrite);
      end else
        if p <> nil then
          Dispose(p);
    end;
  end else
  begin
    if AllowOverwrite then
      TInterlocked.Exchange<V>(p^.Value,Value)
    else
      raise EKeyExists<K>.Create(Key);
  end;
end;

procedure THash<K, V>.SetMap(Key: K; const Value: V; AllowOverwrite: boolean);
var
  sw : TSpinWait;
begin
  sw.Reset;
  SetMap(Key, Value, nil, sw, AllowOverwrite);
end;

procedure THash<K, V>.SetMap(Key: K; const Value: V);
begin
  SetMap(Key, Value, True);
end;

function THash<K, V>.SwapItemsArray(NewItems: PItemArray): PItemArray;
var
 bSuccess : boolean;
 sw : TSpinWait;
begin
  sw.Reset;
  bSuccess := False;
  repeat
    Result := FItems;
    Tinterlocked.CompareExchange<K,V>(FItems,NewItems,FItems,bSuccess);
    if not bSuccess then
      sw.SpinCycle;
  until bSuccess;
end;

procedure THash<K, V>.Visit(const visitor: TVisitorProc<K,V>);
var
  p : PItem;
  del : boolean;
  i : integer;
  sw : TSpinWait;
  lst : TList<PItem>;
begin
  lst := TList<PItem>.Create;
  try
    for i := low(FItems^) to High(FItems^) do
    begin
      p := FItems^[i];
      if p <> nil then
      begin
        repeat
          del := False;
          TInterlocked.Increment(p^.Visiting);
          try
            visitor(p^.Key, p^.Value, del);
            if del then
            begin
              TInterlocked.Increment(p^.Removed);
              lst.Add(p);
              sw.Reset;
              while p^.Visiting <> 1 do
                sw.SpinCycle;
            end;
          finally
            TInterlocked.Decrement(p^.Visiting);
          end;
          p := p^.Next;
        until p = nil
      end;
    end;
    for i := 0 to lst.Count-1 do
    begin
      Remove(lst[i]^.Key);
    end;
  finally
    lst.Free;
  end;
end;

{ EKeyExists<K> }

constructor EKeyExists<K>.Create(Key: K);
type
  PObject = ^TObject;
var
  sKey : string;
  pti : PTypeInfo;
begin
  pti := TypeInfo(K);

  case pti^.Kind of
    tkInteger,
    tkEnumeration:
      sKey := Integer(PInteger(@Key)^).ToString;
    tkInt64 :
      sKey := Int64(PInt64(@Key)^).ToString;

    tkFloat:
      sKey := Double(PDouble(@Key)^).ToString;

    tkChar,
    tkString,
    tkWChar,
    tkLString,
    tkWString,
    tkUString:
      sKey := String(PString(@Key)^);

    tkClass,
    tkClassRef :
      sKey := TObject(PObject(@Key)^).ToString;

    else
      sKey := '';
  end;

  inherited Create('Value exists for key '+sKey);
end;

end.

