object FormMain: TFormMain
  Left = 0
  Top = 0
  Caption = 'Import Excel → Firebird'
  ClientHeight = 620
  ClientWidth = 860
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  object PanelTop: TPanel
    Left = 0
    Top = 0
    Width = 860
    Height = 80
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object LabelPath: TLabel
      Left = 12
      Top = 14
      Width = 139
      Height = 17
      Caption = 'Dossier des fichiers Excel :'
    end
    object EditDataPath: TEdit
      Left = 12
      Top = 36
      Width = 620
      Height = 25
      TabOrder = 0
    end
    object BtnBrowse: TButton
      Left = 642
      Top = 34
      Width = 90
      Height = 29
      Caption = 'Parcourir…'
      TabOrder = 1
      OnClick = BtnBrowseClick
    end
    object BtnStart: TButton
      Left = 746
      Top = 34
      Width = 100
      Height = 29
      Caption = 'Démarrer'
      Default = True
      TabOrder = 2
      OnClick = BtnStartClick
    end
  end
  object ProgressBar: TProgressBar
    Left = 0
    Top = 80
    Width = 860
    Height = 10
    Align = alTop
    TabOrder = 1
  end
  object LabelStatus: TLabel
    Left = 12
    Top = 97
    Width = 200
    Height = 17
    Caption = 'Prêt.'
  end
  object MemoLog: TMemo
    Left = 0
    Top = 120
    Width = 860
    Height = 500
    Align = alBottom
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Courier New'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 2
    WordWrap = False
  end
end
