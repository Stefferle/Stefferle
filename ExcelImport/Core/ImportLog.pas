unit ImportLog;

{$SCOPEDENUMS ON}

interface

uses
  System.Classes, System.SysUtils,
  ImportTypes;

type
  TNewLineEvent = reference to procedure(const ALine: string);

  TImportLog = class
  private
    FLines    : TStringList;
    FFilename : string;
    FOnNewLine: TNewLineEvent;
    function LevelStr(ALevel: TLogLevel): string;
  public
    constructor Create(const ALogFilename: string);
    destructor  Destroy; override;

    procedure Log(const ASource, AMsg: string; ALevel: TLogLevel = TLogLevel.Info);
    procedure SaveToFile;

    property Lines    : TStringList  read FLines;
    property OnNewLine: TNewLineEvent read FOnNewLine write FOnNewLine;
  end;

implementation

constructor TImportLog.Create(const ALogFilename: string);
begin
  inherited Create;
  FFilename := ALogFilename;
  FLines    := TStringList.Create;
end;

destructor TImportLog.Destroy;
begin
  SaveToFile;
  FLines.Free;
  inherited;
end;

function TImportLog.LevelStr(ALevel: TLogLevel): string;
begin
  case ALevel of
    TLogLevel.Info   : Result := 'INFO ';
    TLogLevel.Warning: Result := 'WARN ';
    TLogLevel.Error  : Result := 'ERROR';
  else Result := '?????';
  end;
end;

procedure TImportLog.Log(const ASource, AMsg: string; ALevel: TLogLevel);
var
  LLine: string;
begin
  LLine := Format('[%s] %s | %-24s | %s',
    [FormatDateTime('hh:nn:ss.zzz', Now), LevelStr(ALevel), ASource, AMsg]);
  FLines.Add(LLine);
  if Assigned(FOnNewLine) then
    FOnNewLine(LLine);
end;

procedure TImportLog.SaveToFile;
begin
  if FFilename <> '' then
    FLines.SaveToFile(FFilename, TEncoding.UTF8);
end;

end.
