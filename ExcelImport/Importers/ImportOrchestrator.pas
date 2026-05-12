unit ImportOrchestrator;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  ImportContext, BaseImporter;

type
  TImportOrchestrator = class
  private
    FContext     : TImportContext;
    FDataPath    : string;
    FTotalErrors : Integer;
    procedure RunImporter(AImporter: TBaseImporter);
  public
    constructor Create(AContext: TImportContext; const ADataPath: string);
    function Execute: Integer;
  end;

implementation

uses
  ImportTypes,
  ImportEngagements
  // À ajouter ultérieurement :
  // ImportMarches,
  // ImportAccordsCadres,
  ;

constructor TImportOrchestrator.Create(AContext: TImportContext; const ADataPath: string);
begin
  inherited Create;
  FContext     := AContext;
  FDataPath    := IncludeTrailingPathDelimiter(ADataPath);
  FTotalErrors := 0;
end;

procedure TImportOrchestrator.RunImporter(AImporter: TBaseImporter);
begin
  FContext.Log.Log('Orchestrator', Format('▶ Début : %s', [AImporter.SourceName]));
  try
    AImporter.Execute;
    Inc(FTotalErrors, AImporter.Stats.Errors);
    FContext.Log.Log('Orchestrator',
      Format('■ Fin   : %s | %s', [AImporter.SourceName, AImporter.Stats.Summary]));
  except
    on E: Exception do
    begin
      FContext.Log.Log('Orchestrator',
        Format('✗ FATAL : %s — %s', [AImporter.SourceName, E.Message]),
        TLogLevel.Error);
      Inc(FTotalErrors);
    end;
  end;
end;

function TImportOrchestrator.Execute: Integer;
var
  LImporter: TBaseImporter;
begin
  FTotalErrors := 0;

  LImporter := TImportEngagements.Create(FContext, FDataPath + 'EJ.xlsx');
  try RunImporter(LImporter); finally LImporter.Free; end;

  // LImporter := TImportMarches.Create(FContext, FDataPath + 'MAR.xlsx');
  // try RunImporter(LImporter); finally LImporter.Free; end;

  // LImporter := TImportAccordsCadres.Create(FContext, FDataPath + 'AC.xlsx');
  // try RunImporter(LImporter); finally LImporter.Free; end;

  Result := FTotalErrors;
end;

end.
