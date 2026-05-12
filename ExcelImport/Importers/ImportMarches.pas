unit ImportMarches;

{$SCOPEDENUMS ON}

{
  Import: MAR.xlsx → GO_ENTETE (DOCUMENT='EN', LOT=0)

  Un marché est le document parent d'un groupe d'EJ :
    - LOT=0  = ce record marché
    - LOT=1,2,... = les EJ qui lui appartiennent (ImportEngagements)

  Fournit keymap 'Marche' : MARCHE_ID_ELAP → CHRONO du record LOT=0.
  ImportEngagements consomme cette keymap pour affecter le bon CHRONO aux EJ.

  DOSSIER laissé à 0 : le marché agrège des EJ potentiellement multi-dossiers.
}

interface

uses
  BaseImporter, ImportContext;

type
  TImportMarches = class(TBaseImporter)
  private
    FFilename: string;
    function MapStatut(const ARaw: string): string;
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
  SHEET_NAME = 'Marches';
  DOC_TYPE   = 'EN';
  KM_MAR     = 'Marche';

constructor TImportMarches.Create(AContext: TImportContext; const AFilename: string);
begin
  inherited Create(AContext, 'ImportMarches');
  FFilename := AFilename;
end;

function TImportMarches.MapStatut(const ARaw: string): string;
begin
  if      SameText(ARaw, 'NOTIFIE')  then Result := 'S'
  else if SameText(ARaw, 'SOLDE')    then Result := 'R'
  else if SameText(ARaw, 'RESILIE')  then Result := 'R'
  else if SameText(ARaw, 'EN_COURS') then Result := 'P'
  else
  begin
    Result := Copy(UpperCase(Trim(ARaw)), 1, 1);
    if Result = '' then Result := 'P';
    Log(Format('Statut étape "%s" inconnu → "%s"', [ARaw, Result]), TLogLevel.Warning);
  end;
end;

procedure TImportMarches.Execute;
var
  LExcel      : TExcelReader;
  LSheet      : TDataSet;
  LIdMA       : Integer;
  LChrono     : Integer;
  LEngagement : Integer;
begin
  Log('Ouverture: ' + FFilename);
  LExcel := TExcelReader.Create(FFilename);
  try
    LSheet := LExcel.OpenSheet(SHEET_NAME);
    try
      Log(Format('%d marchés à traiter', [LSheet.RecordCount]));

      InTransaction(procedure
      begin
        while not LSheet.Eof do
        begin
          LIdMA := XlInt(LSheet, 'MARCHE_ID_ELAP', -1);
          if LIdMA < 0 then
          begin
            Inc(FStats.Skipped); LSheet.Next; Continue;
          end;
          if FContext.KeyExists(KM_MAR, IntToStr(LIdMA)) then
          begin
            LogRow(IntToStr(LIdMA), 'Doublon MARCHE_ID_ELAP — ignoré', TLogLevel.Warning);
            Inc(FStats.Skipped); LSheet.Next; Continue;
          end;

          try
            LChrono     := GoNextChrono(FContext.Connection, '-1');
            LEngagement := GoNextChrono(FContext.Connection, DOC_TYPE);

            DbExec(FContext.Connection,
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
              ['DOSS',    0,
               'DOC',     DOC_TYPE,
               'CHR',     LChrono,
               'LOT',     0,
               'TIERS',   XlStr(LSheet, 'Code Tiers'),
               'DOCNAT',  'MA',
               'DOCDT',   XlDate(LSheet, 'Date pièce marché'),
               'DOCREF',  XlStr(LSheet, 'N° de marché'),
               'DOCNUM',  XlStr(LSheet, 'N° de lot'),
               'NATOUVR', Copy(XlStr(LSheet, 'Nom de marché'), 1, 255),
               'TVACOD',  0,
               'TVATX',   0,
               'HT',      0,
               'TVA',     0,
               'TTC',     0,
               'STAT',    MapStatut(XlStr(LSheet, 'Code étape')),
               'ENG',     LEngagement,
               'ENGLIEN', Null,
               'ENGTYP',  'MA',
               'EDOSSID', LIdMA,
               'CRDT',    Date]);

            FContext.RegisterKey(KM_MAR, IntToStr(LIdMA), LChrono);
            Inc(FStats.Inserted);

          except
            on E: Exception do
            begin
              LogRow(IntToStr(LIdMA), 'Erreur INSERT: ' + E.Message, TLogLevel.Error);
              Inc(FStats.Errors);
            end;
          end;

          LSheet.Next;
        end;
      end);

    finally
      LSheet.Free;
    end;
  finally
    LExcel.Free;
  end;
  Log(FStats.Summary);
end;

end.
