unit ImportOrchestrator;

{$SCOPEDENUMS ON}

{
  Orchestre tous les importeurs dans le bon ordre de dépendances.
  Pour ajouter un nouvel importeur :
    1. Ajouter son unit dans la clause uses
    2. Instancier et appeler RunImporter dans Execute, au bon endroit
}

interface

uses
  System.SysUtils,
  ImportContext, BaseImporter;

type
  TImportOrchestrator = class
  private
    FContext     : TImportContext;
    FDataPath    : string; // dossier contenant les fichiers Excel
    FTotalErrors : Integer;
    procedure RunImporter(AImporter: TBaseImporter);
  public
    constructor Create(AContext: TImportContext; const ADataPath: string);

    // Lance l'import complet, retourne le nombre total d'erreurs
    function Execute: Integer;
  end;

implementation

uses
  ImportTypes,
  ImportFournisseurs,
  ImportTableDiscriminee
  // Ajoutez vos autres importeurs ici :
  // ImportClients,
  // ImportContrats,
  ;

{ TImportOrchestrator }

constructor TImportOrchestrator.Create(AContext: TImportContext; const ADataPath: string);
begin
  inherited Create;
  FContext     := AContext;
  FDataPath    := IncludeTrailingPathDelimiter(ADataPath);
  FTotalErrors := 0;
end;

procedure TImportOrchestrator.RunImporter(AImporter: TBaseImporter);
begin
  FContext.Log.Log('Orchestrator',
    Format('▶ Début : %s', [AImporter.SourceName]));
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

  // ── Étape 1 : tables de référence / pas de dépendances ──────────────────
  LImporter := TImportFournisseurs.Create(FContext, FDataPath + 'Fournisseurs.xlsx');
  try RunImporter(LImporter); finally LImporter.Free; end;

  // Ajoutez ici les autres tables sans dépendances (ex: Clients, Sites, ...)

  // ── Étape 2 : entités dépendant des tables de référence ─────────────────
  // LImporter := TImportClients.Create(FContext, FDataPath + 'Clients.xlsx');
  // try RunImporter(LImporter); finally LImporter.Free; end;

  // ── Étape 3 : table discriminée — phase 1 (insertions) ──────────────────
  LImporter := TImportObjetsMetier.Create(FContext, FDataPath + 'ObjetsMetier.xlsx');
  try RunImporter(LImporter); finally LImporter.Free; end;

  // ── Étape 4 : table discriminée — phase 2 (résolution FK internes) ───────
  LImporter := TResoudreFK.Create(FContext, FDataPath + 'ObjetsMetier.xlsx');
  try RunImporter(LImporter); finally LImporter.Free; end;

  Result := FTotalErrors;
end;

end.
