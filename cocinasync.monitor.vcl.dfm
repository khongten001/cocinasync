object cocinasync_vcl_monitor: Tcocinasync_vcl_monitor
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsSizeToolWin
  Caption = 'CocinAsync Job Monitor'
  ClientHeight = 294
  ClientWidth = 563
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  FormStyle = fsStayOnTop
  OldCreateOrder = False
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object Splitter1: TSplitter
    AlignWithMargins = True
    Left = 268
    Top = 26
    Height = 260
    Margins.Top = 26
    Margins.Bottom = 8
    ExplicitLeft = 288
    ExplicitTop = 120
    ExplicitHeight = 100
  end
  object Panel2: TPanel
    Left = 0
    Top = 0
    Width = 265
    Height = 294
    Align = alLeft
    BevelOuter = bvNone
    Caption = 'Panel2'
    TabOrder = 0
    object lbQueue: TListBox
      AlignWithMargins = True
      Left = 8
      Top = 30
      Width = 253
      Height = 256
      Margins.Left = 8
      Margins.Top = 4
      Margins.Right = 4
      Margins.Bottom = 8
      Align = alClient
      ItemHeight = 13
      TabOrder = 0
    end
    object Panel1: TPanel
      Left = 0
      Top = 0
      Width = 265
      Height = 26
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 1
      object Label1: TLabel
        Left = 8
        Top = 10
        Width = 36
        Height = 13
        Caption = 'Queue:'
      end
    end
  end
  object Panel3: TPanel
    Left = 274
    Top = 0
    Width = 289
    Height = 294
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 1
    object Panel4: TPanel
      Left = 0
      Top = 0
      Width = 289
      Height = 26
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 0
      object Label2: TLabel
        Left = 8
        Top = 10
        Width = 44
        Height = 13
        Caption = 'Runners:'
      end
    end
    object tvRunners: TTreeView
      AlignWithMargins = True
      Left = 4
      Top = 30
      Width = 277
      Height = 256
      Margins.Left = 4
      Margins.Top = 4
      Margins.Right = 8
      Margins.Bottom = 8
      Align = alClient
      Indent = 19
      TabOrder = 1
    end
  end
end
