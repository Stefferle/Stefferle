unit ImportEngagements;

{$SCOPEDENUMS ON}

{
  Import: EJ.xlsx  →  GO_ENTETE (DOCUMENT='EN') + GO_LIGNES
  Dépendances : aucune pour l'instant (MARCHE = NULL, résolu lors de l'import MAR)

  Structure EJ :
    - Un ID_EJ unique  →  1 GO_ENTETE (DOCUMENT='EN', LOT=0 ou LOT++ si avenant)
    - N lignes Excel pour cet ID_EJ  →  N GO_LIGNES (NUMERO séquentiel global sur CHRONO)

  Gestion des avenants (Avenant_O/N = 'OUI') :
    - L'avenant partage le CHRONO de l'EJ original (pivot : NUMERO_PIECE)
    - LOT : original=0, avenant1=1, avenant2=2, ...
    - ENGAGEMENT_LIEN de l'avenant = ENGAGEMENT du GO_ENTETE original
    - Import en 2 passes : originaux d'abord, avenants ensuite

  Anomalies connues dans la source :
    - NUMERO_PIECE='1','2','3' : des centaines d'ID_EJ avec le même numéro → loggés
    - 379 ID_EJ avec flags Avenant incohérents entre leurs lignes → on prend la valeur majoritaire
    - 4 ID_MA et 26 ID_AC orphelins → FK laissée à NULL avec WARN
}

interface

uses
  BaseImporter, ImportContext;

type
  TImportEngagements = class(TBaseImporter)
  private
    FFilename: string;

    procedure PreloadDossiers;
    procedure PreloadTVA;

    function LookupDossier(const ACodeOpe: string): Integer;
    function LookupTVA(ATauxDecimal: Double): Integer;
    function MapStatut(const ARaw: string): string;

  public
    constructor Create(AContext: TImportContext; const AFilename: string);
    procedure Execute; override;
  end;

implementation

uses
  System.SysUtils, System.Variants, System.Generics.Collections, System.Generics.Defaults, System.Math,
  Data.DB, FireDAC.Comp.Client,
  ExcelReader, DbHelpers, ImportTypes;

const
  SHEET_NAME  = 'Feuille de calcul 1';
  DOC_TYPE    = 'EN';

  TVA_TABLE   = 'TVA_TAUX';
  TVA_ETABL   = 1;

  KM_EJ       = 'EJ';
  KM_EJMETA   = 'EJMeta';

  ANOMALOUS_PIECES : array[0..2] of string = ('1', '2', '3');

type
  TEJLine = record
    CodeOpe            : string;
    CodeTiers          : string;
    DateValidation     : TDateTime;
    NumeroPieceComplet : string;
    NumeroPiece        : string;
    Objet              : string;
    EstAvenant         : Boolean;
    TypeBilan          : Integer;
    Compte             : string;
    Imputation         : string;
    MontantHT          : Double;
    MontantTVA         : Double;
    MontantTTC         : Double;
    TauxTVA            : Double;
    Niveau1            : string;
    EtapeWF            : string;
    Statut             : string;
    NumPiecMA          : string;
    IdMA               : Integer;
    IdAC               : Integer;
    IdEJ               : Integer;
    CodeDest           : string;
    CodeNature         : string;
  end;

  TEJGroup = TList<TEJLine>;

constructor TImportEngagements.Create(AContext: TImportContext; const AFilename: string);
begin
  inherited Create(AContext, 'ImportEngagements');
  FFilename := AFilename;
end;

procedure TImportEngagements.PreloadDossiers;
var
  Q: TFDQuery;
begin
  Log('Pré-chargement GO_DOSSIER…');
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FContext.Connection;
    Q.SQL.Text   := 'SELECT CLE, CODE FROM GO_DOSSIER';
    Q.Open;
    while not Q.Eof do
    begin
      FContext.RegisterKey('DOSSIER',
        Trim(Q.FieldByName('CODE').AsString),
        Q.FieldByName('CLE').AsInteger);
      Q.Next;
    end;
    Log(Format('  %d dossiers chargés', [Q.RecordCount]));
  finally
    Q.Free;
  end;
end;

procedure TImportEngagements.PreloadTVA;
var
  Q    : TFDQuery;
  LTaux: Double;
begin
  Log('Pré-chargement ' + TVA_TABLE + '…');
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FContext.Connection;
    Q.SQL.Text   := 'SELECT CLE, TAUX FROM ' + TVA_TABLE +
                    ' WHERE CLE_ETABLISSEMENT = ' + IntToStr(TVA_ETABL);
    Q.Open;
    while not Q.Eof do
    begin
      LTaux := Q.FieldByName('TAUX').AsFloat;
      FContext.RegisterKey('TVA',
        Format('%.3f', [LTaux]),
        Q.FieldByName('CLE').AsInteger);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TImportEngagements.LookupDossier(const ACodeOpe: string): Integer;
begin
  Result := FContext.ResolveKey('DOSSIER', Trim(ACodeOpe));
  if Result < 0 then
    Log(Format('CODE_OPE "%s" non trouvé dans GO_DOSSIER → DOSSIER=0', [ACodeOpe]),
      TLogLevel.Warning);
  if Result < 0 then Result := 0;
end;

function TImportEngagements.LookupTVA(ATauxDecimal: Double): Integer;
var
  LKey: string;
begin
  LKey   := Format('%.3f', [ATauxDecimal * 100]);
  Result := FContext.ResolveKey('TVA', LKey);
  if Result < 0 then
  begin
    Log(Format('Taux TVA %.4f (%.3f%%) non trouvé dans %s → TVA_CODE=0',
      [ATauxDecimal, ATauxDecimal * 100, TVA_TABLE]),
      TLogLevel.Warning);
    Result := 0;
  end;
end;

function TImportEngagements.MapStatut(const ARaw: string): string;
begin
  if      ARaw = 'R' then Result := 'R'
  else if ARaw = 'P' then Result := 'P'
  else if ARaw = 'S' then Result := 'S'
  else
  begin
    Result := ARaw;
    if Length(Result) > 1 then
    begin
      Log(Format('Statut "%s" tronqué à 1 caractère', [ARaw]), TLogLevel.Warning);
      Result := Copy(Result, 1, 1);
    end;
  end;
end;

function IsAnomalousPiece(const P: string): Boolean;
var
  S: string;
begin
  for S in ANOMALOUS_PIECES do
    if P = S then Exit(True);
  Result := False;
end;

function ReadLine(DS: TDataSet): TEJLine;
begin
  Result.CodeOpe             := XlKey(DS, 'CODE_OPE');
  Result.CodeTiers           := XlStr(DS, 'CODE_TIERS');
  Result.DateValidation      := XlDate(DS, 'DATE_VALIDATION');
  Result.NumeroPieceComplet  := XlStr(DS, 'NUMERO_PIECE_COMPLET');
  Result.NumeroPiece         := XlStr(DS, 'NUMERO_PIECE');
  Result.Objet               := XlStr(DS, 'OBJET');
  Result.EstAvenant          := SameText(XlStr(DS, 'Avenant_(O/N)'), 'OUI');
  Result.TypeBilan           := XlInt(DS, 'TYPE_BILAN', 1);
  Result.Compte              := XlStr(DS, 'COMPTE');
  Result.Imputation          := XlStr(DS, 'IMPUTATION');
  Result.MontantHT           := XlFloat(DS, 'VAL_CONSO_MONTANT_HT');
  Result.MontantTVA          := XlFloat(DS, 'VAL_CONSO_MONTANT_TVA');
  Result.MontantTTC          := XlFloat(DS, 'VAL_CONSO_MONTANT_TTC');
  Result.TauxTVA             := XlFloat(DS, 'TAUX_TVA');
  Result.Niveau1             := XlStr(DS, 'NIVEAU 1');
  Result.EtapeWF             := XlStr(DS, 'ETAPE_WF_CODE');
  Result.Statut              := XlStr(DS, 'STATUT');
  Result.NumPiecMA           := XlStr(DS, 'NUMERO_PIECE_MA');
  Result.IdMA                := XlInt(DS, 'ID_MA', -1);
  Result.IdAC                := XlInt(DS, 'ID_AC', -1);
  Result.IdEJ                := XlInt(DS, 'ID_EJ', -1);
  Result.CodeDest            := XlStr(DS, 'CODE_DEST');
  Result.CodeNature          := XlStr(DS, 'CODE_NATURE');
end;

procedure InsertGroup(
  Ctx         : TImportContext;
  const Group : TEJGroup;
  AChrono     : Integer;
  ALot        : Integer;
  AEngagement : Integer;
  AEngLien    : Integer;
  AStartNumero: Integer;
  ADossier    : Integer;
  ATVACle     : Integer;
  ATauxTVA    : Double;
  const AStatut: string
);
var
  L       : TEJLine;
  TotalHT : Double;
  TotalTVA: Double;
  TotalTTC: Double;
  LNumero : Integer;
begin
  if Group.Count = 0 then Exit;
  L := Group[0];

  TotalHT := 0; TotalTVA := 0; TotalTTC := 0;
  for var LLine in Group do
  begin
    TotalHT  := TotalHT  + LLine.MontantHT;
    TotalTVA := TotalTVA + LLine.MontantTVA;
    TotalTTC := TotalTTC + LLine.MontantTTC;
  end;

  DbExec(Ctx.Connection,
    'INSERT INTO GO_ENTETE (' +
    '  DOSSIER, DOCUMENT, CHRONO, LOT,' +
    '  TIERS, DOC_NATURE, DOC_DATE, DOC_REFERENCE, DOC_NUMERO,' +
    '  NATURE_OUVRAGE, TVA_CODE, TVA_TAUX,' +
    '  HT, TVA, TTC,' +
    '  STATUS, ENGAGEMENT, ENGAGEMENT_LIEN, ENGAGEMENT_TYPE,' +
    '  E_DOSSIERID, CREATION_DATE' +
    ') VALUES (' +
    '  :DOSS,:DOC,:CHR,:LOT,' +
    '  :TIERS,:DOCNAT,:DOCDT,:DOCREF,:DOCNUM,' +
    '  :NATOUVR,:TVACOD,:TVATX,' +
    '  :HT,:TVA,:TTC,' +
    '  :STAT,:ENG,:ENGLIEN,:ENGTYP,' +
    '  :EDOSSID,:CRDT' +
    ')',
    ['DOSS',    ADossier,
     'DOC',     DOC_TYPE,
     'CHR',     AChrono,
     'LOT',     ALot,
     'TIERS',   L.CodeTiers,
     'DOCNAT',  'EJ',
     'DOCDT',   L.DateValidation,
     'DOCREF',  L.NumeroPieceComplet,
     'DOCNUM',  L.NumeroPiece,
     'NATOUVR', Copy(L.Objet, 1, 255),
     'TVACOD',  ATVACle,
     'TVATX',   ATauxTVA,
     'HT',      TotalHT,
     'TVA',     TotalTVA,
     'TTC',     TotalTTC,
     'STAT',    AStatut,
     'ENG',     AEngagement,
     'ENGLIEN', IfThen(AEngLien < 0, Null, AEngLien),
     'ENGTYP',  'EJ',
     'EDOSSID', L.IdEJ,
     'CRDT',    Date]);

  LNumero := AStartNumero;
  for var LLine in Group do
  begin
    DbExec(Ctx.Connection,
      'INSERT INTO GO_LIGNES (' +
      '  DOSSIER, DOCUMENT, CHRONO, NUMERO,' +
      '  TYPE_BILAN, POSTE_BILAN, IMPUTATION,' +
      '  LOT, LIBELLE,' +
      '  TVA_CODE, TVA_TAUX,' +
      '  HT, TVA, TTC,' +
      '  SECTION, TRANCHE' +
      ') VALUES (' +
      '  :DOSS,:DOC,:CHR,:NUM,' +
      '  :TYBIL,:PBIL,:IMPUT,' +
      '  :LOT,:LIB,' +
      '  :TVACOD,:TVATX,' +
      '  :HT,:TVA,:TTC,' +
      '  :SECT,:TRANCH' +
      ')',
      ['DOSS',   ADossier,
       'DOC',    DOC_TYPE,
       'CHR',    AChrono,
       'NUM',    LNumero,
       'TYBIL',  LLine.TypeBilan,
       'PBIL',   Copy(LLine.Compte,     1, 15),
       'IMPUT',  Copy(LLine.Imputation, 1, 15),
       'LOT',    ALot,
       'LIB',    Copy(LLine.Objet,      1, 40),
       'TVACOD', ATVACle,
       'TVATX',  ATauxTVA,
       'HT',     LLine.MontantHT,
       'TVA',    LLine.MontantTVA,
       'TTC',    LLine.MontantTTC,
       'SECT',   Copy(LLine.Niveau1,    1, 15),
       'TRANCH', LNumero]);
    Inc(LNumero);
  end;
end;

procedure TImportEngagements.Execute;
var
  LExcel    : TExcelReader;
  LSheet    : TDataSet;
  LLine     : TEJLine;
  LGroups   : TObjectDictionary<Integer, TEJGroup>;
  LIdOrder  : TList<Integer>;
  LGrp      : TEJGroup;
  LIdEJ     : Integer;
  type
    TEngRef = record
      Chrono     : Integer;
      Engagement : Integer;
      NextLot    : Integer;
      NextNumero : Integer;
    end;
  var
    LPieceMap  : TDictionary<string, TEngRef>;
    LRef       : TEngRef;
  LDossier    : Integer;
  LTVACle     : Integer;
  LTauxTVA    : Double;
  LStatut     : string;
  LChrono     : Integer;
  LEngagement : Integer;
  LEngLien    : Integer;
  LLot        : Integer;
  LStartNum   : Integer;
  LPiece      : string;
  LIsAvenant  : Boolean;
  LOuiCount   : Integer;

begin
  PreloadDossiers;
  PreloadTVA;

  Log('Ouverture: ' + FFilename);
  LExcel := TExcelReader.Create(FFilename);
  try
    LSheet := LExcel.OpenSheet(SHEET_NAME);
    try
      Log(Format('%d lignes brutes lues', [LSheet.RecordCount]));

      LGroups  := TObjectDictionary<Integer, TEJGroup>.Create([doOwnsValues]);
      LIdOrder := TList<Integer>.Create;
      try
        while not LSheet.Eof do
        begin
          LLine := ReadLine(LSheet);
          LIdEJ := LLine.IdEJ;
          if LIdEJ < 0 then
          begin
            Inc(FStats.Skipped); LSheet.Next; Continue;
          end;
          if not LGroups.TryGetValue(LIdEJ, LGrp) then
          begin
            LGrp := TEJGroup.Create;
            LGroups.Add(LIdEJ, LGrp);
            LIdOrder.Add(LIdEJ);
          end;
          LGrp.Add(LLine);
          LSheet.Next;
        end;

        Log(Format('%d ID_EJ distincts regroupés', [LGroups.Count]));

        LIdOrder.Sort(TComparer<Integer>.Construct(
          function(const A, B: Integer): Integer
          var GA, GB: TEJGroup; OuiA, OuiB: Integer;
          begin
            LGroups.TryGetValue(A, GA); LGroups.TryGetValue(B, GB);
            OuiA := 0; OuiB := 0;
            for var L in GA do if L.EstAvenant then Inc(OuiA);
            for var L in GB do if L.EstAvenant then Inc(OuiB);
            if (OuiA * 2 < GA.Count) and (OuiB * 2 >= GB.Count) then Result := -1
            else if (OuiA * 2 >= GA.Count) and (OuiB * 2 < GB.Count) then Result := 1
            else Result := 0;
          end));

        LPieceMap := TDictionary<string, TEngRef>.Create;
        try
          InTransaction(procedure
          begin
            for var LCurId in LIdOrder do
            begin
              LGroups.TryGetValue(LCurId, LGrp);
              if LGrp.Count = 0 then Continue;
              LLine := LGrp[0];

              LOuiCount := 0;
              for var II := 0 to LGrp.Count - 1 do
                if LGrp[II].EstAvenant then Inc(LOuiCount);
              LIsAvenant := (LOuiCount * 2) >= LGrp.Count;

              LPiece   := LLine.NumeroPiece;
              LDossier := LookupDossier(LLine.CodeOpe);
              LTauxTVA := LLine.TauxTVA;
              LTVACle  := LookupTVA(LTauxTVA);
              LStatut  := MapStatut(LLine.Statut);

              if LIsAvenant and not IsAnomalousPiece(LPiece)
                and LPieceMap.TryGetValue(LPiece, LRef) then
              begin
                LChrono     := LRef.Chrono;
                LLot        := LRef.NextLot;
                LEngLien    := LRef.Engagement;
                LEngagement := GoNextChrono(FContext.Connection, DOC_TYPE);
                LStartNum   := LRef.NextNumero;
                LRef.NextLot    := LRef.NextLot + 1;
                LRef.NextNumero := LRef.NextNumero + LGrp.Count;
                LPieceMap.AddOrSetValue(LPiece, LRef);
                LogRow(IntToStr(LCurId),
                  Format('Avenant LOT=%d sur CHRONO=%d (pièce=%s)', [LLot, LChrono, LPiece]));
              end
              else
              begin
                LChrono     := GoNextChrono(FContext.Connection, '-1');
                LEngagement := GoNextChrono(FContext.Connection, DOC_TYPE);
                LLot        := 0;
                LEngLien    := -1;
                LStartNum   := 1;
                if LIsAvenant then
                  LogRow(IntToStr(LCurId),
                    Format('Avenant sans original connu (pièce=%s) → inséré LOT=0', [LPiece]),
                    TLogLevel.Warning);
                if not IsAnomalousPiece(LPiece) then
                begin
                  LRef.Chrono     := LChrono;
                  LRef.Engagement := LEngagement;
                  LRef.NextLot    := 1;
                  LRef.NextNumero := LGrp.Count + 1;
                  LPieceMap.AddOrSetValue(LPiece, LRef);
                end;
              end;

              try
                InsertGroup(FContext, LGrp,
                  LChrono, LLot, LEngagement, LEngLien, LStartNum,
                  LDossier, LTVACle, LTauxTVA, LStatut);
                FContext.RegisterKey(KM_EJ,    IntToStr(LCurId), LChrono);
                FContext.RegisterKey(KM_EJMETA, IntToStr(LCurId), LEngagement);
                Inc(FStats.Inserted);
              except
                on E: Exception do
                begin
                  LogRow(IntToStr(LCurId), 'Erreur INSERT: ' + E.Message, TLogLevel.Error);
                  Inc(FStats.Errors);
                end;
              end;
            end;
          end);
        finally
          LPieceMap.Free;
        end;
      finally
        LGroups.Free;
        LIdOrder.Free;
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
