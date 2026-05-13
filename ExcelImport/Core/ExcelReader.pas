unit ExcelReader;

{
  Lecture Excel (.xlsx) native — sans dépendance externe.
  Format xlsx = archive ZIP contenant des fichiers XML (OOXML).
  Retourne un TFDMemTable (TDataSet) avec HDR=YES implicite.

  Prérequis : aucun driver tiers. Delphi 10.3+ suffit.
}

interface

uses
  System.SysUtils, System.Classes,
  Data.DB,
  FireDAC.Comp.Client;

type
  TExcelReader = class
  private
    FFilename: string;
    function ReadFile(const AInternalPath: string): string;
    function GetSheetRid(const AWorkbookXml, ASheetName: string): string;
    function GetSheetFilename(const ARelsXml, ARid: string): string;
    function ParseSharedStrings(const AXml: string): TArray<string>;
    procedure PopulateTable(const ASheetXml: string;
      const ASharedStrings: TArray<string>; ATable: TFDMemTable);
    function ColIndex(const AColRef: string): Integer;
    function XlDateToDateTime(ASerial: Double): TDateTime;
  public
    constructor Create(const AFilename: string);
    function OpenSheet(const ASheetName: string): TDataSet;
    function GetSheetNames: TArray<string>;
  end;

function XlStr  (DS: TDataSet; const ACol: string; const ADefault: string    = ''   ): string;
function XlInt  (DS: TDataSet; const ACol: string; ADefault: Integer          = 0    ): Integer;
function XlFloat(DS: TDataSet; const ACol: string; ADefault: Double           = 0    ): Double;
function XlDate (DS: TDataSet; const ACol: string; ADefault: TDateTime        = 0    ): TDateTime;
function XlBool (DS: TDataSet; const ACol: string; ADefault: Boolean          = False): Boolean;
function XlKey  (DS: TDataSet; const ACol: string): string;

implementation

uses
  System.Zip, System.Math, System.StrUtils,
  Xml.XMLDoc, Xml.XMLIntf;

{ ── helpers XML ─────────────────────────────────────────────────────────── }

function LoadXml(const AText: string): IXMLDocument;
begin
  Result := TXMLDocument.Create(nil);
  Result.Active := False;
  Result.LoadFromXML(AText);
  Result.Active := True;
end;

function AttrStr(ANode: IXMLNode; const AAttr: string): string;
begin
  if ANode.HasAttribute(AAttr) then
    Result := ANode.Attributes[AAttr]
  else
    Result := '';
end;

{ ── TExcelReader ─────────────────────────────────────────────────────────── }

constructor TExcelReader.Create(const AFilename: string);
begin
  inherited Create;
  FFilename := AFilename;
  if not FileExists(FFilename) then
    raise Exception.CreateFmt('Fichier introuvable : %s', [FFilename]);
end;

function TExcelReader.ReadFile(const AInternalPath: string): string;
var
  LZip   : TZipFile;
  LStream: TStream;
  LBytes : TBytes;
begin
  LZip := TZipFile.Create;
  try
    LZip.Open(FFilename, zmRead);
    try
      LZip.Read(AInternalPath, LBytes);
      Result := TEncoding.UTF8.GetString(LBytes);
    finally
      LZip.Close;
    end;
  finally
    LZip.Free;
  end;
end;

function TExcelReader.GetSheetRid(const AWorkbookXml, ASheetName: string): string;
var
  LDoc  : IXMLDocument;
  LSheets: IXMLNode;
  I     : Integer;
  LNode : IXMLNode;
begin
  Result := '';
  LDoc := LoadXml(AWorkbookXml);
  LSheets := LDoc.DocumentElement.ChildNodes.FindNode('sheets');
  if LSheets = nil then Exit;
  for I := 0 to LSheets.ChildNodes.Count - 1 do
  begin
    LNode := LSheets.ChildNodes[I];
    if SameText(AttrStr(LNode, 'name'), ASheetName) then
    begin
      Result := AttrStr(LNode, 'r:id');
      Exit;
    end;
  end;
end;

function TExcelReader.GetSheetFilename(const ARelsXml, ARid: string): string;
var
  LDoc  : IXMLDocument;
  LRels : IXMLNode;
  I     : Integer;
  LNode : IXMLNode;
begin
  Result := '';
  LDoc := LoadXml(ARelsXml);
  LRels := LDoc.DocumentElement;
  for I := 0 to LRels.ChildNodes.Count - 1 do
  begin
    LNode := LRels.ChildNodes[I];
    if AttrStr(LNode, 'Id') = ARid then
    begin
      Result := AttrStr(LNode, 'Target');
      Exit;
    end;
  end;
end;

function TExcelReader.ParseSharedStrings(const AXml: string): TArray<string>;
var
  LDoc  : IXMLDocument;
  LSst  : IXMLNode;
  I, J  : Integer;
  LSi   : IXMLNode;
  LText : string;
  LChild: IXMLNode;
begin
  SetLength(Result, 0);
  if AXml = '' then Exit;
  LDoc := LoadXml(AXml);
  LSst := LDoc.DocumentElement;
  SetLength(Result, LSst.ChildNodes.Count);
  for I := 0 to LSst.ChildNodes.Count - 1 do
  begin
    LSi   := LSst.ChildNodes[I];
    LText := '';
    // <si> peut contenir <t> ou plusieurs <r><t>
    for J := 0 to LSi.ChildNodes.Count - 1 do
    begin
      LChild := LSi.ChildNodes[J];
      if SameText(LChild.LocalName, 't') then
        LText := LText + LChild.Text
      else if SameText(LChild.LocalName, 'r') then
      begin
        // rich text : extraire le <t> interne
        var LT := LChild.ChildNodes.FindNode('t');
        if LT <> nil then LText := LText + LT.Text;
      end;
    end;
    Result[I] := LText;
  end;
end;

function TExcelReader.ColIndex(const AColRef: string): Integer;
var
  C: Char;
begin
  Result := 0;
  for C in AColRef do
  begin
    if C < 'A' then Break;
    Result := Result * 26 + (Ord(C) - Ord('A') + 1);
  end;
  Dec(Result); // 0-based
end;

function TExcelReader.XlDateToDateTime(ASerial: Double): TDateTime;
begin
  // Excel epoch : 30 décembre 1899 (+ correction bug Lotus 1-2-3 pour 1900-02-29)
  if ASerial >= 60 then
    Result := ASerial - 2  // correction post-28-fév-1900
  else
    Result := ASerial - 1;
  Result := EncodeDate(1900, 1, 0) + Result;
end;

procedure TExcelReader.PopulateTable(const ASheetXml: string;
  const ASharedStrings: TArray<string>; ATable: TFDMemTable);
var
  LDoc       : IXMLDocument;
  LSheetData : IXMLNode;
  LRows      : IXMLNode;
  LRow       : IXMLNode;
  LCell      : IXMLNode;
  I, R, C    : Integer;
  LHeaders   : TArray<string>;
  LMaxCol    : Integer;
  LRef       : string;
  LColIdx    : Integer;
  LType      : string;
  LVal       : string;
  LFieldName : string;
  LDblVal    : Double;

  function ExtractColLetters(const ACellRef: string): string;
  var Ch: Char;
  begin
    Result := '';
    for Ch in ACellRef do
      if Ch in ['A'..'Z'] then Result := Result + Ch
      else Break;
  end;

begin
  LDoc := LoadXml(ASheetXml);

  // Trouver sheetData
  LSheetData := nil;
  for I := 0 to LDoc.DocumentElement.ChildNodes.Count - 1 do
    if SameText(LDoc.DocumentElement.ChildNodes[I].LocalName, 'sheetData') then
    begin
      LSheetData := LDoc.DocumentElement.ChildNodes[I];
      Break;
    end;
  if (LSheetData = nil) or (LSheetData.ChildNodes.Count = 0) then Exit;

  // ── Passe 1 : lire l'en-tête (première ligne) ───────────────────────────
  LRows    := LSheetData;
  LMaxCol  := 0;
  LRow     := LRows.ChildNodes[0]; // première ligne = en-têtes
  SetLength(LHeaders, 0);

  for C := 0 to LRow.ChildNodes.Count - 1 do
  begin
    LCell   := LRow.ChildNodes[C];
    LRef    := AttrStr(LCell, 'r');
    LColIdx := ColIndex(ExtractColLetters(LRef));
    if LColIdx > LMaxCol then LMaxCol := LColIdx;
  end;

  SetLength(LHeaders, LMaxCol + 1);
  for C := 0 to LRow.ChildNodes.Count - 1 do
  begin
    LCell   := LRow.ChildNodes[C];
    LRef    := AttrStr(LCell, 'r');
    LColIdx := ColIndex(ExtractColLetters(LRef));
    LType   := AttrStr(LCell, 't');
    var LValNode := LCell.ChildNodes.FindNode('v');
    if LValNode <> nil then
    begin
      LVal := LValNode.Text;
      if LType = 's' then
      begin
        var Idx := StrToIntDef(LVal, -1);
        if (Idx >= 0) and (Idx < Length(ASharedStrings)) then
          LVal := ASharedStrings[Idx];
      end;
    end
    else
      LVal := '';
    LHeaders[LColIdx] := Trim(LVal);
  end;

  // ── Créer les champs dans TFDMemTable ───────────────────────────────────
  ATable.FieldDefs.Clear;
  for C := 0 to High(LHeaders) do
  begin
    LFieldName := LHeaders[C];
    if LFieldName = '' then
      LFieldName := 'F' + IntToStr(C + 1);
    ATable.FieldDefs.Add(LFieldName, ftString, 1024);
  end;
  ATable.CreateDataSet;
  ATable.Open;

  // ── Passe 2 : lire les données ──────────────────────────────────────────
  for R := 1 to LRows.ChildNodes.Count - 1 do
  begin
    LRow := LRows.ChildNodes[R];
    ATable.Append;
    for C := 0 to LRow.ChildNodes.Count - 1 do
    begin
      LCell   := LRow.ChildNodes[C];
      LRef    := AttrStr(LCell, 'r');
      LColIdx := ColIndex(ExtractColLetters(LRef));
      LType   := AttrStr(LCell, 't');
      var LStyleIdx := AttrStr(LCell, 's');

      var LValNode := LCell.ChildNodes.FindNode('v');
      if LValNode <> nil then
        LVal := LValNode.Text
      else
      begin
        // cellule avec <is><t>...</t></is> (inline string)
        var LIs := LCell.ChildNodes.FindNode('is');
        if LIs <> nil then
        begin
          var LT := LIs.ChildNodes.FindNode('t');
          if LT <> nil then LVal := LT.Text else LVal := '';
        end
        else
          LVal := '';
      end;

      if LType = 's' then
      begin
        // shared string
        var Idx := StrToIntDef(LVal, -1);
        if (Idx >= 0) and (Idx < Length(ASharedStrings)) then
          LVal := ASharedStrings[Idx]
        else
          LVal := '';
      end
      else if (LType = '') and (LVal <> '') then
      begin
        // numérique — vérifier si c'est une date via le style
        // On stocke la valeur brute ; XlDate() fera la conversion si besoin
        // Pas de conversion ici pour ne pas casser XlFloat/XlInt
      end
      else if LType = 'b' then
        LVal := LVal  // booléen : '0' ou '1'
      else if LType = 'str' then
      begin
        // formule résolue — garder LVal tel quel
      end;

      if (LColIdx <= High(LHeaders)) and (LHeaders[LColIdx] <> '') then
      begin
        LFieldName := LHeaders[LColIdx];
        if LFieldName = '' then LFieldName := 'F' + IntToStr(LColIdx + 1);
        var F := ATable.FindField(LFieldName);
        if F <> nil then
          F.AsString := LVal;
      end;
    end;
    ATable.Post;
  end;

  ATable.First;
end;

function TExcelReader.OpenSheet(const ASheetName: string): TDataSet;
var
  LWorkbookXml : string;
  LRelsXml     : string;
  LSharedStrXml: string;
  LSheetXml    : string;
  LRid         : string;
  LTarget      : string;
  LSheetPath   : string;
  LTable       : TFDMemTable;
begin
  LWorkbookXml  := ReadFile('xl/workbook.xml');
  LRelsXml      := ReadFile('xl/_rels/workbook.xml.rels');
  LRid          := GetSheetRid(LWorkbookXml, ASheetName);
  if LRid = '' then
    raise Exception.CreateFmt('Onglet "%s" introuvable dans %s',
      [ASheetName, FFilename]);

  LTarget := GetSheetFilename(LRelsXml, LRid);
  if LTarget.StartsWith('worksheets/') then
    LSheetPath := 'xl/' + LTarget
  else
    LSheetPath := 'xl/worksheets/' + LTarget;

  LSharedStrXml := '';
  try LSharedStrXml := ReadFile('xl/sharedStrings.xml'); except end;

  LSheetXml := ReadFile(LSheetPath);

  LTable := TFDMemTable.Create(nil);
  try
    PopulateTable(LSheetXml, ParseSharedStrings(LSharedStrXml), LTable);
    Result := LTable;
  except
    LTable.Free;
    raise;
  end;
end;

function TExcelReader.GetSheetNames: TArray<string>;
var
  LDoc   : IXMLDocument;
  LSheets: IXMLNode;
  I      : Integer;
begin
  SetLength(Result, 0);
  LDoc := LoadXml(ReadFile('xl/workbook.xml'));
  LSheets := LDoc.DocumentElement.ChildNodes.FindNode('sheets');
  if LSheets = nil then Exit;
  SetLength(Result, LSheets.ChildNodes.Count);
  for I := 0 to LSheets.ChildNodes.Count - 1 do
    Result[I] := AttrStr(LSheets.ChildNodes[I], 'name');
end;

{ ── fonctions helpers (interface inchangée) ─────────────────────────────── }

function XlStr(DS: TDataSet; const ACol: string; const ADefault: string): string;
var
  F: TField;
begin
  F := DS.FindField(ACol);
  if (F = nil) or F.IsNull or (Trim(F.AsString) = '') then Result := ADefault
  else Result := Trim(F.AsString);
end;

function XlInt(DS: TDataSet; const ACol: string; ADefault: Integer): Integer;
var
  S: string;
begin
  S := XlStr(DS, ACol);
  if S = '' then Result := ADefault
  else
  begin
    // Supprimer éventuelle partie décimale (.0)
    var P := Pos('.', S);
    if P > 0 then S := Copy(S, 1, P - 1);
    Result := StrToIntDef(S, ADefault);
  end;
end;

function XlFloat(DS: TDataSet; const ACol: string; ADefault: Double): Double;
var
  S: string;
begin
  S := XlStr(DS, ACol);
  if S = '' then Result := ADefault
  else
  begin
    S := StringReplace(S, ',', '.', [rfReplaceAll]); // normaliser séparateur
    if not TryStrToFloat(S, Result) then Result := ADefault;
  end;
end;

function XlDate(DS: TDataSet; const ACol: string; ADefault: TDateTime): TDateTime;
var
  S   : string;
  D   : Double;
  Reader: TExcelReader;
begin
  S := XlStr(DS, ACol);
  if S = '' then
    Result := ADefault
  else if TryStrToFloat(S, D) then
  begin
    // Valeur numérique Excel → date
    if D >= 60 then D := D - 2 else D := D - 1;
    Result := EncodeDate(1900, 1, 0) + D;
  end
  else
  begin
    // Essayer de parser comme date texte
    try Result := StrToDateTime(S);
    except Result := ADefault; end;
  end;
end;

function XlBool(DS: TDataSet; const ACol: string; ADefault: Boolean): Boolean;
var
  S: string;
begin
  S := UpperCase(Trim(XlStr(DS, ACol)));
  if S = '' then Result := ADefault
  else Result := (S = 'OUI') or (S = 'YES') or (S = '1')
              or (S = 'TRUE') or (S = 'VRAI') or (S = 'X');
end;

function XlKey(DS: TDataSet; const ACol: string): string;
begin
  Result := UpperCase(Trim(XlStr(DS, ACol)));
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
end;

end.
