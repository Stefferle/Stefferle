unit MainForm;

{$SCOPEDENUMS ON}

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.IniFiles,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.FileCtrl, Vcl.Menus,
  FireDAC.Comp.Client, FireDAC.Phys.FB,
  ImportLog, ImportContext, ImportOrchestrator, ImportTypes;

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
    AppMenu     : TMainMenu;
    MenuOptions : TMenuItem;
    MenuConfigDb: TMenuItem;
    procedure BtnBrowseClick(Sender: TObject);
    procedure BtnStartClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure MenuConfigDbClick(Sender: TObject);
  private
    FConnection: TFDConnection;
    FDbFile    : string;
    FDbUser    : string;
    FDbPass    : string;
    FDbCharset : string;
    function  IniPath: string;
    procedure LoadIni;
    procedure SaveIni;
    procedure SetupConnection;
    procedure AppendLog(const ALine: string);
    procedure SetRunning(ARunning: Boolean);
    procedure UpdateCaption;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

uses
  System.UITypes;

{ TFormMain }

function TFormMain.IniPath: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

procedure TFormMain.LoadIni;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(IniPath);
  try
    FDbFile    := LIni.ReadString('Database', 'File',     '');
    FDbUser    := LIni.ReadString('Database', 'User',     'SYSDBA');
    FDbPass    := LIni.ReadString('Database', 'Password', 'masterkey');
    FDbCharset := LIni.ReadString('Database', 'Charset',  'UTF8');
    EditDataPath.Text := LIni.ReadString('App', 'DataPath', '');
  finally
    LIni.Free;
  end;
end;

procedure TFormMain.SaveIni;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(IniPath);
  try
    LIni.WriteString('Database', 'File',     FDbFile);
    LIni.WriteString('Database', 'User',     FDbUser);
    LIni.WriteString('Database', 'Password', FDbPass);
    LIni.WriteString('Database', 'Charset',  FDbCharset);
    LIni.WriteString('App',      'DataPath', EditDataPath.Text);
  finally
    LIni.Free;
  end;
end;

procedure TFormMain.UpdateCaption;
var
  LDb: string;
begin
  LDb := FDbFile;
  if LDb = '' then LDb := '(non configurée)';
  Caption := Format('Import Excel → Firebird  [%s]', [ExtractFileName(LDb)]);
end;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  FConnection := TFDConnection.Create(nil);
  LoadIni;
  UpdateCaption;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  SaveIni;
  FConnection.Free;
end;

procedure TFormMain.SetupConnection;
begin
  if FDbFile = '' then
    raise Exception.CreateFmt(
      'Base de données non configurée.%sUtilisez Options > Paramètres DB…',
      [sLineBreak]);
  FConnection.Close;
  with FConnection.Params do
  begin
    Clear;
    Add('DriverID=FB');
    Add('Database='     + FDbFile);
    Add('User_Name='    + FDbUser);
    Add('Password='     + FDbPass);
    Add('CharacterSet=' + FDbCharset);
  end;
  FConnection.Open;
end;

procedure TFormMain.AppendLog(const ALine: string);
begin
  TThread.Synchronize(nil, procedure
  begin
    MemoLog.Lines.Add(ALine);
    SendMessage(MemoLog.Handle, WM_VSCROLL, SB_BOTTOM, 0);
  end);
end;

procedure TFormMain.SetRunning(ARunning: Boolean);
begin
  BtnStart.Enabled     := not ARunning;
  BtnBrowse.Enabled    := not ARunning;
  EditDataPath.Enabled := not ARunning;
  MenuConfigDb.Enabled := not ARunning;
  if ARunning then
    ProgressBar.Style := pbstMarquee
  else
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
    LLog         : TImportLog;
    LContext     : TImportContext;
    LOrchestrator: TImportOrchestrator;
    LErrors      : Integer;
    LLogFile     : string;
  begin
    LLogFile := IncludeTrailingPathDelimiter(LDataPath) +
      FormatDateTime('yyyymmdd_hhnnss', Now) + '_import.log';
    LLog := TImportLog.Create(LLogFile);
    try
      LLog.OnNewLine := AppendLog;

      try
        SetupConnection;
      except
        on E: Exception do
        begin
          LLog.Log('Connexion', 'Impossible d''ouvrir la base : ' + E.Message,
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
      LLog.Free;
    end;
  end).Start;
end;

procedure TFormMain.MenuConfigDbClick(Sender: TObject);
var
  LFile, LUser, LPass: string;
begin
  LFile := FDbFile;
  LUser := FDbUser;
  LPass := FDbPass;

  if not InputQuery('Paramètres DB (1/3)', 'Chemin complet du fichier .fdb :', LFile) then Exit;
  if not InputQuery('Paramètres DB (2/3)', 'Utilisateur Firebird :', LUser) then Exit;
  if not InputQuery('Paramètres DB (3/3)', 'Mot de passe :', LPass) then Exit;

  FDbFile := LFile;
  FDbUser := LUser;
  FDbPass := LPass;

  SaveIni;
  UpdateCaption;
  ShowMessage('Paramètres enregistrés dans ' + IniPath);
end;

end.
