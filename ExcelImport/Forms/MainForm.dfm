object FormMain: TFormMain
  Left = 0
  Top = 0
  Margins.Left = 5
  Margins.Top = 5
  Margins.Right = 5
  Margins.Bottom = 5
  Caption = 'Import Excel'#8594'Firebird'
  ClientHeight = 1085
  ClientWidth = 1519
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -23
  Font.Name = 'Segoe UI'
  Font.Style = []
  Menu = AppMenu
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 168
  TextHeight = 31
  object LabelStatus: TLabel
    Left = 21
    Top = 170
    Width = 46
    Height = 31
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 'Pr'#234't.'
  end
  object PanelTop: TPanel
    Left = 0
    Top = 0
    Width = 1519
    Height = 140
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object LabelPath: TLabel
      Left = 21
      Top = 25
      Width = 265
      Height = 31
      Margins.Left = 5
      Margins.Top = 5
      Margins.Right = 5
      Margins.Bottom = 5
      Caption = 'Dossier des fichiers Excel :'
    end
    object EditDataPath: TEdit
      Left = 21
      Top = 63
      Width = 1085
      Height = 39
      Margins.Left = 5
      Margins.Top = 5
      Margins.Right = 5
      Margins.Bottom = 5
      TabOrder = 0
    end
    object BtnBrowse: TButton
      Left = 1124
      Top = 60
      Width = 157
      Height = 50
      Margins.Left = 5
      Margins.Top = 5
      Margins.Right = 5
      Margins.Bottom = 5
      Caption = 'Parcourir'#8230
      TabOrder = 1
      OnClick = BtnBrowseClick
    end
    object BtnStart: TButton
      Left = 1306
      Top = 60
      Width = 175
      Height = 50
      Margins.Left = 5
      Margins.Top = 5
      Margins.Right = 5
      Margins.Bottom = 5
      Caption = 'D'#233'marrer'
      Default = True
      TabOrder = 2
      OnClick = BtnStartClick
    end
  end
  object ProgressBar: TProgressBar
    Left = 0
    Top = 140
    Width = 1519
    Height = 18
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Align = alTop
    TabOrder = 1
  end
  object MemoLog: TMemo
    Left = 0
    Top = 210
    Width = 1519
    Height = 875
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Align = alBottom
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -21
    Font.Name = 'Courier New'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 2
    WordWrap = False
  end
  object AppMenu: TMainMenu
    Left = 400
    Top = 10
    object MenuOptions: TMenuItem
      Caption = 'Options'
      object MenuConfigDb: TMenuItem
        Caption = 'Param'#232'tres DB'#8230
        OnClick = MenuConfigDbClick
      end
    end
  end
end
