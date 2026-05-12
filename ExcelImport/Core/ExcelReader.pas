unit ExcelReader;

{
  Lecture Excel via ADO / Microsoft ACE OLEDB 12.0.
  Prérequis: "Microsoft Access Database Engine 2016 Redistributable" installé
  (ou toute version Office avec ACE).
  Pas de dépendance à Office ni à des librairies tierces.
}

interface

uses
  System.SysUtils, System.Variants, System.Classes,
  Data.DB, Data.Win.ADODB;

type
  TExcelReader = class
  private
    FConnection: TADOConnection;
    FFilename  : string;
    function BuildConnectionString: string;
  public
    constructor Create(const AFilename: string);
    destructor  Destroy; override;

    function OpenSheet(const ASheetName: string): TADODataSet;
    function GetSheetNames: TArray<string>;
  end;

function XlStr  (DS: TDataSet; const ACol: string; const ADefault: string   = ''   ): string;
function XlInt  (DS: TDataSet; const ACol: string; ADefault: Integer         = 0    ): Integer;
function XlFloat(DS: TDataSet; const ACol: string; ADefault: Double          = 0    ): Double;
function XlDate (DS: TDataSet; const ACol: string; ADefault: TDateTime       = 0    ): TDateTime;
function XlBool (DS: TDataSet; const ACol: string; ADefault: Boolean         = False): Boolean;
function XlKey(DS: TDataSet; const ACol: string): string;

implementation

uses
  System.StrUtils, Data.Win.ADODB;

constructor TExcelReader.Create(const AFilename: string);
begin
  inherited Create;
  FFilename   := AFilename;
  FConnection := TADOConnection.Create(nil);
  FConnection.LoginPrompt      := False;
  FConnection.ConnectionString := BuildConnectionString;
  FConnection.Open;
end;

destructor TExcelReader.Destroy;
begin
  FConnection.Close;
  FConnection.Free;
  inherited;
end;

function TExcelReader.BuildConnectionString: string;
begin
  Result := Format(
    'Provider=Microsoft.ACE.OLEDB.12.0;Data Source=%s;' +
    'Extended Properties="Excel 12.0;HDR=YES;IMEX=1"',
    [FFilename]);
end;

function TExcelReader.OpenSheet(const ASheetName: string): TADODataSet;
var
  LRef: string;
begin
  if ASheetName.EndsWith('$') then
    LRef := '[' + ASheetName + ']'
  else
    LRef := '[' + ASheetName + '$]';

  Result := TADODataSet.Create(nil);
  try
    Result.Connection   := FConnection;
    Result.CommandText  := 'SELECT * FROM ' + LRef;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function TExcelReader.GetSheetNames: TArray<string>;
var
  LSchema: TADODataSet;
  LNames : TStringList;
  LName  : string;
begin
  LNames := TStringList.Create;
  try
    LSchema := TADODataSet.Create(nil);
    try
      LSchema.Recordset :=
        (FConnection.ConnectionObject as _Connection)
          .OpenSchema(20, EmptyParam, EmptyParam);
      while not LSchema.Eof do
      begin
        LName := LSchema.FieldByName('TABLE_NAME').AsString;
        if LName.EndsWith('$') then
          LNames.Add(Copy(LName, 1, Length(LName) - 1));
        LSchema.Next;
      end;
    finally
      LSchema.Free;
    end;
    Result := LNames.ToStringArray;
  finally
    LNames.Free;
  end;
end;

function XlStr(DS: TDataSet; const ACol: string; const ADefault: string): string;
var
  F: TField;
begin
  F := DS.FindField(ACol);
  if (F = nil) or F.IsNull then Result := ADefault
  else Result := Trim(F.AsString);
end;

function XlInt(DS: TDataSet; const ACol: string; ADefault: Integer): Integer;
var
  F: TField;
begin
  F := DS.FindField(ACol);
  if (F = nil) or F.IsNull then Result := ADefault
  else try Result := F.AsInteger; except Result := ADefault; end;
end;

function XlFloat(DS: TDataSet; const ACol: string; ADefault: Double): Double;
var
  F: TField;
begin
  F := DS.FindField(ACol);
  if (F = nil) or F.IsNull then Result := ADefault
  else try Result := F.AsFloat; except Result := ADefault; end;
end;

function XlDate(DS: TDataSet; const ACol: string; ADefault: TDateTime): TDateTime;
var
  F: TField;
begin
  F := DS.FindField(ACol);
  if (F = nil) or F.IsNull then Result := ADefault
  else try Result := F.AsDateTime; except Result := ADefault; end;
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
