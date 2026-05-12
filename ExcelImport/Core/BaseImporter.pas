unit BaseImporter;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  ImportTypes, ImportContext;

type
  TBaseImporter = class
  protected
    FContext   : TImportContext;
    FStats     : TImportStats;
    FSourceName: string;

    procedure Log(const AMsg: string; ALevel: TLogLevel = TLogLevel.Info);
    procedure LogRow(const AExcelKey, AMsg: string;
      ALevel: TLogLevel = TLogLevel.Info);
    procedure InTransaction(AProc: TProc);

  public
    constructor Create(AContext: TImportContext; const ASourceName: string);
    procedure Execute; virtual; abstract;
    property Stats     : TImportStats read FStats;
    property SourceName: string       read FSourceName;
  end;

implementation

constructor TBaseImporter.Create(AContext: TImportContext; const ASourceName: string);
begin
  inherited Create;
  FContext    := AContext;
  FSourceName := ASourceName;
  FStats.Reset;
end;

procedure TBaseImporter.Log(const AMsg: string; ALevel: TLogLevel);
begin
  FContext.Log.Log(FSourceName, AMsg, ALevel);
end;

procedure TBaseImporter.LogRow(const AExcelKey, AMsg: string; ALevel: TLogLevel);
begin
  FContext.Log.Log(FSourceName,
    Format('[%-20s] %s', [AExcelKey, AMsg]), ALevel);
end;

procedure TBaseImporter.InTransaction(AProc: TProc);
begin
  FContext.Connection.StartTransaction;
  try
    AProc();
    FContext.Connection.Commit;
  except
    FContext.Connection.Rollback;
    raise;
  end;
end;

end.
