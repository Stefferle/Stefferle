unit ImportFournisseurs;

{$SCOPEDENUMS ON}

{
  Import: Fournisseurs.xlsx  →  TABLE_TIERS  (TYPE_TIERS = 'FOU')
  Dépendances : aucune (à exécuter en premier)
  Fournit     : keymap 'Fournisseur'  (clé Excel → ID Firebird)
               afin que les importeurs suivants puissent résoudre les FK.
}

interface

uses
  BaseImporter, ImportContext;

type
  TImportFournisseurs = class(TBaseImporter)
  private
    FFilename: string;

    // ── Règles métier ────────────────────────────────────────────────────────
    // Chaque méthode MapXxx est isolée pour être facile à modifier.

    function NormalizeCode(const ARaw: string): string;
    function MapCategorie(const AExcelCat: string): string;
    function MapPays(const AExcelPays: string): string;

  public
    constructor Create(AContext: TImportContext; const AFilename: string);
    procedure Execute; override;
  end;

implementation

uses
  System.SysUtils, System.Variants,
  Data.DB,
  ExcelReader, DbHelpers, ImportTypes;

const
  ENTITY_NAME = 'Fournisseur'; // nom de la keymap dans le contexte
  TYPE_TIERS  = 'FOU';
  GENERATOR   = 'GEN_TIERS_ID';
  SHEET_NAME  = 'Fournisseurs';

{ TImportFournisseurs }

constructor TImportFournisseurs.Create(AContext: TImportContext; const AFilename: string);
begin
  inherited Create(AContext, 'ImportFournisseurs');
  FFilename := AFilename;
end;

// ── Règles métier ─────────────────────────────────────────────────────────────

function TImportFournisseurs.NormalizeCode(const ARaw: string): string;
begin
  Result := UpperCase(StringReplace(ARaw, '-', '', [rfReplaceAll]));
end;

function TImportFournisseurs.MapCategorie(const AExcelCat: string): string;
begin
  if      AExcelCat = 'Matières premières' then Result := 'MATP'
  else if AExcelCat = 'Sous-traitant'      then Result := 'SOUS'
  else if AExcelCat = 'Prestataire'        then Result := 'PRES'
  else
  begin
    Result := 'AUTR';
    Log(Format('Catégorie inconnue "%s" → AUTR', [AExcelCat]), TLogLevel.Warning);
  end;
end;

function TImportFournisseurs.MapPays(const AExcelPays: string): string;
begin
  if (AExcelPays = 'France')    or (AExcelPays = 'FR') then Result := 'FR'
  else if (AExcelPays = 'Allemagne') or (AExcelPays = 'DE') then Result := 'DE'
  else if (AExcelPays = 'Espagne')   or (AExcelPays = 'ES') then Result := 'ES'
  else
  begin
    Result := UpperCase(Trim(AExcelPays));
    if Result <> '' then
      Log(Format('Pays non mappé "%s" conservé tel quel', [AExcelPays]), TLogLevel.Warning);
  end;
end;

// ── Boucle principale ─────────────────────────────────────────────────────────

procedure TImportFournisseurs.Execute;
var
  LExcel   : TExcelReader;
  LSheet   : TDataSet;
  LKey     : string;
  LNewId   : Integer;
begin
  Log('Ouverture: ' + FFilename);

  LExcel := TExcelReader.Create(FFilename);
  try
    LSheet := LExcel.OpenSheet(SHEET_NAME);
    try
      Log(Format('%d lignes à traiter', [LSheet.RecordCount]));

      while not LSheet.Eof do
      begin
        LKey := XlKey(LSheet, 'CODE_FOURNISSEUR');

        // ── Lignes à ignorer ───────────────────────────────────────────────
        if LKey = '' then
        begin
          Inc(FStats.Skipped); LSheet.Next; Continue;
        end;
        if FContext.KeyExists(ENTITY_NAME, LKey) then
        begin
          LogRow(LKey, 'Doublon — ignoré', TLogLevel.Warning);
          Inc(FStats.Skipped); LSheet.Next; Continue;
        end;

        // ── Écriture ───────────────────────────────────────────────────────
        try
          LNewId := DbNextId(FContext.Connection, GENERATOR);

          DbExec(FContext.Connection,
            'INSERT INTO TABLE_TIERS (' +
            '  ID, TYPE_TIERS, CODE, NOM, CATEGORIE, PAYS, EMAIL, TELEPHONE, ACTIF' +
            ') VALUES (' +
            '  :ID, :TT, :CODE, :NOM, :CAT, :PAYS, :EMAIL, :TEL, :ACTIF' +
            ')',
            ['ID',    LNewId,
             'TT',    TYPE_TIERS,
             'CODE',  NormalizeCode(XlStr(LSheet, 'CODE_FOURNISSEUR')),
             'NOM',   XlStr(LSheet, 'NOM_FOURNISSEUR'),
             'CAT',   MapCategorie(XlStr(LSheet, 'CATEGORIE')),
             'PAYS',  MapPays(XlStr(LSheet, 'PAYS')),
             'EMAIL', LowerCase(Trim(XlStr(LSheet, 'EMAIL'))),
             'TEL',   XlStr(LSheet, 'TELEPHONE'),
             'ACTIF', Ord(XlBool(LSheet, 'ACTIF', True))]);

          FContext.RegisterKey(ENTITY_NAME, LKey, LNewId);
          Inc(FStats.Inserted);

        except
          on E: Exception do
          begin
            LogRow(LKey, 'Erreur INSERT: ' + E.Message, TLogLevel.Error);
            Inc(FStats.Errors);
          end;
        end;

        LSheet.Next;
      end;

    finally
      LSheet.Free;
    end;
  finally
    LExcel.Free;
  end;

  Log(FStats.Summary);
end;

end.
