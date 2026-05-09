unit DbHelpers;

{
  Helpers FireDAC pour Firebird.
  Convention DbExec : les paramètres sont passés en paires alternées name/value.
    DbExec(Conn, 'INSERT INTO T(A,B) VALUES(:A,:B)', ['A', 1, 'B', 'texte']);
}

interface

uses
  System.SysUtils, System.Variants,
  FireDAC.Comp.Client;

// Exécute une requête DML avec paramètres nommés (paires nom/valeur)
procedure DbExec(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant);

// Lit la prochaine valeur d'un générateur Firebird
function DbNextId(Conn: TFDConnection; const AGeneratorName: string): Integer;

// Retourne le premier champ de la première ligne, ou Null si aucune ligne
function DbScalar(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant): Variant;

// Retourne vrai si au moins une ligne correspond à la requête
function DbExists(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant): Boolean;

implementation

procedure ApplyParams(Q: TFDQuery; const AParams: array of Variant);
var
  I: Integer;
begin
  Assert((Length(AParams) mod 2) = 0,
    'DbHelpers: les paramètres doivent être des paires nom/valeur');
  I := 0;
  while I < Length(AParams) do
  begin
    Q.ParamByName(VarToStr(AParams[I])).Value := AParams[I + 1];
    Inc(I, 2);
  end;
end;

procedure DbExec(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant);
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text   := ASQL;
    ApplyParams(Q, AParams);
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

function DbNextId(Conn: TFDConnection; const AGeneratorName: string): Integer;
begin
  Result := DbScalar(Conn,
    'SELECT NEXT VALUE FOR ' + AGeneratorName + ' FROM RDB$DATABASE', []);
end;

function DbScalar(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant): Variant;
var
  Q: TFDQuery;
begin
  Result := Null;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text   := ASQL;
    ApplyParams(Q, AParams);
    Q.Open;
    if not Q.IsEmpty then
      Result := Q.Fields[0].Value;
  finally
    Q.Free;
  end;
end;

function DbExists(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant): Boolean;
begin
  Result := not VarIsNull(DbScalar(Conn, ASQL, AParams));
end;

end.
