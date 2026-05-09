unit ImportTableDiscriminee;

{$SCOPEDENUMS ON}

{
  Cas complexe : une seule table (TABLE_OBJET_METIER, 100+ colonnes) accueille
  plusieurs sous-objets métier distingués par la colonne TYPE_OBJ.

  Exemple de types :
    'CONT'  = Contrat        (colonnes A..Z remplies, colonnes AA..AZ à NULL)
    'AVNT'  = Avenant        (dépend d'un CONT via FK_PARENT_ID)
    'ANEXE' = Annexe         (dépend d'un CONT ou d'un AVNT)

  Un AVNT peut également référencer un autre AVNT dans la même table
  (ex: colonne FK_AVNT_PRECEDENT_ID).

  Stratégie d'import en deux phases :
    Phase 1 — Insertion de toutes les lignes ; les FK internes sont laissées à NULL.
    Phase 2 — UPDATE des FK internes une fois toutes les clés enregistrées.

  Chaque sous-type a sa propre méthode BuildXxx qui retourne les valeurs à
  écrire. Modifier ou ajouter une règle = modifier uniquement cette méthode.
}

interface

uses
  BaseImporter, ImportContext;

// ── Phase 1 : insertion ───────────────────────────────────────────────────────

type
  TImportObjetsMetier = class(TBaseImporter)
  private
    FFilename: string;

    // Produit les valeurs communes à tous les types
    procedure FillChampsCommunsParams(DS: TObject;
      out ACode, ALibelle, AStatut: string; out ADateDebut, ADateFin: TDateTime);

    // Chaque sous-type a ses propres champs spécialisés
    procedure InsereContrat(DS: TObject; const AKey: string; AId: Integer);
    procedure InsereAvenant(DS: TObject; const AKey: string; AId: Integer);
    procedure InsereAnnexe(DS: TObject; const AKey: string; AId: Integer);

    function MapStatut(const ARaw: string): string;

  public
    constructor Create(AContext: TImportContext; const AFilename: string);
    procedure Execute; override;
  end;

// ── Phase 2 : résolution des FK internes ─────────────────────────────────────

type
  TResoudreFK = class(TBaseImporter)
  private
    FFilename: string;
    procedure ResoudreAvenants(DS: TObject);
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
  TABLE       = 'TABLE_OBJET_METIER';
  GENERATOR   = 'GEN_OBJET_ID';
  SHEET_NAME  = 'ObjetsMetier';

  // Noms des keymaps dans le contexte (une par type)
  KM_CONTRAT  = 'Contrat';
  KM_AVENANT  = 'Avenant';
  KM_ANNEXE   = 'Annexe';

{ TImportObjetsMetier }

constructor TImportObjetsMetier.Create(AContext: TImportContext; const AFilename: string);
begin
  inherited Create(AContext, 'ImportObjetsMetier');
  FFilename := AFilename;
end;

function TImportObjetsMetier.MapStatut(const ARaw: string): string;
begin
  if      ARaw = 'En cours'    then Result := 'ENC'
  else if ARaw = 'Signé'       then Result := 'SIG'
  else if ARaw = 'Résilié'     then Result := 'RES'
  else if ARaw = 'Expiré'      then Result := 'EXP'
  else
  begin
    Result := 'INC'; // inconnu
    Log(Format('Statut inconnu "%s" → INC', [ARaw]), TLogLevel.Warning);
  end;
end;

procedure TImportObjetsMetier.InsereContrat(DS: TObject; const AKey: string; AId: Integer);
var
  LDS    : TDataSet absolute DS;
  LMtAnn : Double;
  LDuree : Integer;
begin
  LMtAnn := XlFloat(LDS, 'MONTANT_ANNUEL');
  LDuree := XlInt  (LDS, 'DUREE_MOIS');

  DbExec(FContext.Connection,
    'INSERT INTO ' + TABLE + ' (' +
    '  ID, TYPE_OBJ, CODE, LIBELLE, STATUT, DATE_DEBUT, DATE_FIN,' +
    '  MONTANT_ANNUEL, DUREE_MOIS,' +
    '  FK_PARENT_ID' +               // NULL en phase 1
    ') VALUES (' +
    '  :ID,:TYP,:CODE,:LIB,:STAT,:DDEB,:DFIN,' +
    '  :MTANN,:DUR,' +
    '  NULL' +
    ')',
    ['ID',    AId,
     'TYP',   'CONT',
     'CODE',  XlStr(LDS, 'CODE_CONTRAT'),
     'LIB',   XlStr(LDS, 'LIBELLE'),
     'STAT',  MapStatut(XlStr(LDS, 'STATUT')),
     'DDEB',  XlDate(LDS, 'DATE_DEBUT'),
     'DFIN',  XlDate(LDS, 'DATE_FIN'),
     'MTANN', LMtAnn,
     'DUR',   LDuree]);

  FContext.RegisterKey(KM_CONTRAT, AKey, AId);
  Inc(FStats.Inserted);
end;

procedure TImportObjetsMetier.InsereAvenant(DS: TObject; const AKey: string; AId: Integer);
var
  LDS: TDataSet absolute DS;
begin
  // FK_PARENT_ID (→ Contrat) sera résolu en phase 2 via KM_CONTRAT
  // FK_AVNT_PRECEDENT_ID (→ Avenant) aussi en phase 2 via KM_AVENANT
  DbExec(FContext.Connection,
    'INSERT INTO ' + TABLE + ' (' +
    '  ID, TYPE_OBJ, CODE, LIBELLE, STATUT, DATE_DEBUT, DATE_FIN,' +
    '  AVENANT_NUM, OBJET_AVENANT,' +
    '  FK_PARENT_ID, FK_AVNT_PRECEDENT_ID' + // NULL — remplis phase 2
    ') VALUES (' +
    '  :ID,:TYP,:CODE,:LIB,:STAT,:DDEB,:DFIN,' +
    '  :AVNUM,:OBJAV,' +
    '  NULL, NULL' +
    ')',
    ['ID',    AId,
     'TYP',   'AVNT',
     'CODE',  XlStr(LDS, 'CODE_AVENANT'),
     'LIB',   XlStr(LDS, 'LIBELLE'),
     'STAT',  MapStatut(XlStr(LDS, 'STATUT')),
     'DDEB',  XlDate(LDS, 'DATE_DEBUT'),
     'DFIN',  XlDate(LDS, 'DATE_FIN'),
     'AVNUM', XlInt(LDS, 'NUM_AVENANT'),
     'OBJAV', XlStr(LDS, 'OBJET')]);

  FContext.RegisterKey(KM_AVENANT, AKey, AId);
  Inc(FStats.Inserted);
end;

procedure TImportObjetsMetier.InsereAnnexe(DS: TObject; const AKey: string; AId: Integer);
var
  LDS: TDataSet absolute DS;
begin
  DbExec(FContext.Connection,
    'INSERT INTO ' + TABLE + ' (' +
    '  ID, TYPE_OBJ, CODE, LIBELLE, STATUT,' +
    '  ANNEXE_TYPE, ANNEXE_REF,' +
    '  FK_PARENT_ID' + // NULL — rempli phase 2
    ') VALUES (' +
    '  :ID,:TYP,:CODE,:LIB,:STAT,' +
    '  :ATYP,:AREF,' +
    '  NULL' +
    ')',
    ['ID',   AId,
     'TYP',  'ANEX',
     'CODE', XlStr(LDS, 'CODE_ANNEXE'),
     'LIB',  XlStr(LDS, 'LIBELLE'),
     'STAT', MapStatut(XlStr(LDS, 'STATUT')),
     'ATYP', XlStr(LDS, 'TYPE_ANNEXE'),
     'AREF', XlStr(LDS, 'REFERENCE')]);

  FContext.RegisterKey(KM_ANNEXE, AKey, AId);
  Inc(FStats.Inserted);
end;

procedure TImportObjetsMetier.Execute;
var
  LExcel  : TExcelReader;
  LSheet  : TDataSet;
  LKey    : string;
  LType   : string;
  LNewId  : Integer;
begin
  Log('Ouverture: ' + FFilename);

  LExcel := TExcelReader.Create(FFilename);
  try
    LSheet := LExcel.OpenSheet(SHEET_NAME);
    try
      Log(Format('%d lignes à traiter', [LSheet.RecordCount]));

      while not LSheet.Eof do
      begin
        LType := UpperCase(Trim(XlStr(LSheet, 'TYPE_OBJET')));
        LKey  := LType + '|' + XlKey(LSheet, 'CODE_OBJET'); // clé composite

        if LKey = (LType + '|') then
        begin
          Inc(FStats.Skipped); LSheet.Next; Continue;
        end;

        try
          LNewId := DbNextId(FContext.Connection, GENERATOR);

          if      LType = 'CONT' then InsereContrat(LSheet, LKey, LNewId)
          else if LType = 'AVNT' then InsereAvenant(LSheet, LKey, LNewId)
          else if LType = 'ANEX' then InsereAnnexe (LSheet, LKey, LNewId)
          else
          begin
            LogRow(LKey, Format('Type inconnu "%s" — ligne ignorée', [LType]),
              TLogLevel.Error);
            Inc(FStats.Errors);
          end;

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

{ TResoudreFK — Phase 2 }

constructor TResoudreFK.Create(AContext: TImportContext; const AFilename: string);
begin
  inherited Create(AContext, 'ResoudreFK');
  FFilename := AFilename;
end;

procedure TResoudreFK.ResoudreAvenants(DS: TObject);
var
  LDS          : TDataSet absolute DS;
  LKeyAvenant  : string;
  LKeyContrat  : string;
  LKeyPrecedent: string;
  LIdAvenant   : Integer;
  LIdContrat   : Integer;
  LIdPrecedent : Integer;
begin
  while not LDS.Eof do
  begin
    if UpperCase(Trim(XlStr(LDS, 'TYPE_OBJET'))) <> 'AVNT' then
    begin
      LDS.Next; Continue;
    end;

    LKeyAvenant   := 'AVNT|' + XlKey(LDS, 'CODE_OBJET');
    LKeyContrat   := 'CONT|' + XlKey(LDS, 'CODE_CONTRAT_PARENT');
    LKeyPrecedent := 'AVNT|' + XlKey(LDS, 'CODE_AVENANT_PRECEDENT');

    LIdAvenant := FContext.ResolveKey(KM_AVENANT, LKeyAvenant);
    if LIdAvenant < 0 then
    begin
      LogRow(LKeyAvenant, 'ID introuvable dans la keymap', TLogLevel.Error);
      Inc(FStats.Errors); LDS.Next; Continue;
    end;

    // FK_PARENT_ID (contrat)
    LIdContrat := FContext.ResolveKey(KM_CONTRAT, LKeyContrat);
    if LIdContrat < 0 then
      LogRow(LKeyAvenant,
        Format('Contrat parent "%s" introuvable', [LKeyContrat]),
        TLogLevel.Warning)
    else
      DbExec(FContext.Connection,
        'UPDATE ' + TABLE + ' SET FK_PARENT_ID = :PID WHERE ID = :ID',
        ['PID', LIdContrat, 'ID', LIdAvenant]);

    // FK_AVNT_PRECEDENT_ID (optionnel)
    if XlKey(LDS, 'CODE_AVENANT_PRECEDENT') <> '' then
    begin
      LIdPrecedent := FContext.ResolveKey(KM_AVENANT, LKeyPrecedent);
      if LIdPrecedent < 0 then
        LogRow(LKeyAvenant,
          Format('Avenant précédent "%s" introuvable', [LKeyPrecedent]),
          TLogLevel.Warning)
      else
        DbExec(FContext.Connection,
          'UPDATE ' + TABLE + ' SET FK_AVNT_PRECEDENT_ID = :PID WHERE ID = :ID',
          ['PID', LIdPrecedent, 'ID', LIdAvenant]);
    end;

    Inc(FStats.Updated);
    LDS.Next;
  end;
end;

procedure TResoudreFK.Execute;
var
  LExcel : TExcelReader;
  LSheet : TDataSet;
begin
  Log('Résolution des FK internes (phase 2)');

  LExcel := TExcelReader.Create(FFilename);
  try
    LSheet := LExcel.OpenSheet(SHEET_NAME);
    try
      ResoudreAvenants(LSheet);
      // Ajoutez ResoudreAnnexes(LSheet) ici si les annexes ont aussi des FK
    finally
      LSheet.Free;
    end;
  finally
    LExcel.Free;
  end;

  Log(FStats.Summary);
end;

end.
