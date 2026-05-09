unit MainForm;

{$SCOPEDENUMS ON}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.FileCtrl,
  FireDAC.Comp.Client, FireDAC.Drivers.FB,
  ImportLog, ImportContext, ImportOrchestrator;

type
  TFormMain = class(TForm)
    PanelTop    : TPanel;
    LabelPath   : TLabel;
    EditDataPath: TEdit;
    BtnBrowse   : TButton;
    BtnStart    : TButton;
    ProgressBar : TProgressBar;
    LabelStatus : TLabel;
    MemoLog     : TMemo;
    procedure BtnBrowseClick(Sender: TObject);
    procedure BtnStartClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FConnection: TFDConnection;
    procedure SetupConnection;
    procedure AppendLog(const ALine: string);
    procedure SetRunning(ARunning: Boolean);
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

uses
  System.UITypes;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  FConnection := TFDConnection.Create(nil);
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  FConnection.Free;
end;

procedure TFormMain.SetupConnection;
begin
  FConnection.Close;
  with FConnection.Params do
  begin
    Clear;
    Add('DriverID=FB');
    // ── Adapter ces paramètres à votre base ────────────────────────────────
    Add('Database=C:\Databases\MaBase.fdb');
    Add('User_Name=SYSDBA');
    Add('Password=masterkey');
    Add('CharacterSet=UTF8');
    // ──────────────────────────────────────────────────────────────────────
  end;
  FConnection.Open;
end;

procedure TFormMain.AppendLog(const ALine: string);
begin
  // Peut être appelé depuis un thread — PostMessage pour sécurité
  TThread.Synchronize(nil, procedure
  begin
    MemoLog.Lines.Add(ALine);
    // Scroll automatique vers la dernière ligne
    SendMessage(MemoLog.Handle, WM_VSCROLL, SB_BOTTOM, 0);
  end);
end;

procedure TFormMain.SetRunning(ARunning: Boolean);
begin
  BtnStart.Enabled    := not ARunning;
  BtnBrowse.Enabled   := not ARunning;
  EditDataPath.Enabled:= not ARunning;
  ProgressBar.Style   := TProgressBarStyle(Ord(ARunning)); // pbstMarquee quand actif
  if not ARunning then
    ProgressBar.Style := pbstNormal;
end;

procedure TFormMain.BtnBrowseClick(Sender: TObject);
var
  LDir: string;
begin
  LDir := EditDataPath.Text;
  if SelectDirectory('Dossier des fichiers Excel', '', LDir) then
    EditDataPath.Text := LDir;
end;

procedure TFormMain.BtnStartClick(Sender: TObject);
var
  LDataPath: string;
begin
  LDataPath := Trim(EditDataPath.Text);
  if LDataPath = '' then
  begin
    ShowMessage('Veuillez choisir le dossier des fichiers Excel.');
    Exit;
  end;

  MemoLog.Clear;
  SetRunning(True);
  LabelStatus.Caption := 'Import en cours…';

  TThread.CreateAnonymousThread(procedure
  var
    LLog        : TImportLog;
    LContext    : TImportContext;
    LOrchestrator: TImportOrchestrator;
    LErrors     : Integer;
    LLogFile    : string;
  begin
    LLogFile := IncludeTrailingPathDelimiter(LDataPath) +
      FormatDateTime('yyyymmdd_hhnnss', Now) + '_import.log';
    LLog := TImportLog.Create(LLogFile);
    try
      LLog.OnNewLine := AppendLog; // affichage en temps réel dans le Memo

      try
        SetupConnection;
      except
        on E: Exception do
        begin
          LLog.Log('Connexion', 'Impossible d'ouvrir la base: ' + E.Message,
            TLogLevel.Error);
          TThread.Synchronize(nil, procedure
          begin
            LabelStatus.Caption := 'Erreur de connexion.';
            SetRunning(False);
          end);
          Exit;
        end;
      end;

      LContext := TImportContext.Create(FConnection, LLog);
      try
        LOrchestrator := TImportOrchestrator.Create(LContext, LDataPath);
        try
          LErrors := LOrchestrator.Execute;
        finally
          LOrchestrator.Free;
        end;
      finally
        LContext.Free;
      end;

      TThread.Synchronize(nil, procedure
      begin
        if LErrors = 0 then
          LabelStatus.Caption := 'Import terminé sans erreur.'
        else
          LabelStatus.Caption := Format('Import terminé — %d erreur(s). Voir le log.',
            [LErrors]);
        SetRunning(False);
      end);

    finally
      LLog.Free; // sauvegarde le fichier .log
    end;
  end).Start;
end;

end.
