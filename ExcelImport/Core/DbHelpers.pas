unit DbHelpers;

{
  Helpers FireDAC pour Firebird.

  Convention DbExec : paramètres en paires alternées nom/valeur.
    DbExec(Conn, 'INSERT INTO T(A,B) VALUES(:A,:B)', ['A', 1, 'B', 'texte']);

  Séquences via GO_CHRONO (pattern read-increment-update) :
    GoNextChrono(Conn, '-1')  →  CHRONO document (PK GO_ENTETE)
    GoNextChrono(Conn, 'EN')  →  ENGAGEMENT logique
  À appeler à l'intérieur d'une transaction pour éviter les collisions.
}

interface

uses
  System.SysUtils, System.Variants,
  FireDAC.Comp.Client;

// Exécute une requête DML avec paramètres nommés (paires nom/valeur)
procedure DbExec(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant);

// Retourne le premier champ de la première ligne, ou Null si aucune ligne
function DbScalar(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant): Variant;

// Retourne vrai si au moins une ligne correspond à la requête
function DbExists(Conn: TFDConnection; const ASQL: string;
  const AParams: array of Variant): Boolean;

// Lit et incrémente GO_CHRONO pour la clé globale donnée.
//   ADocument = '-1'  → CHRONO document (PK GO_ENTETE)
//   ADocument = 'EN'  → numéro ENGAGEMENT logique
// Lève une exception si la ligne GO_CHRONO est absente.
function GoNextChrono(Conn: TFDConnection; const ADocument: string): Integer;

implementation

const
  // Clé de la ligne GO_CHRONO utilisée pour les compteurs globaux
  GC_ENTREPRISE = -1;
  GC_DOSSIER    = -1;
  GC_ANNEE      = -1;
  GC_MOIS       = -1;

  SQL_CHRONO_READ =
    'SELECT CHRONO FROM GO_CHRONO ' +
    'WHERE ENTREPRISE = :ENT AND DOSSIER = :DOS AND ' +
    '      ANNEE = :ANN AND MOIS = :MOS AND DOCUMENT = :DOC ' +
    'WITH LOCK';                          // verrou optimiste Firebird

  SQL_CHRONO_UPDATE =
    'UPDATE GO_CHRONO SET CHRONO = :NEW_CHRONO ' +
    'WHERE ENTREPRISE = :ENT AND DOSSIER = :DOS AND ' +
    '      ANNEE = :ANN AND MOIS = :MOS AND DOCUMENT = :DOC';

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

function GoNextChrono(Conn: TFDConnection; const ADocument: string): Integer;
var
  Q: TFDQuery;
  LCurrent: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;

    // Lecture avec verrou de la ligne GO_CHRONO
    Q.SQL.Text := SQL_CHRONO_READ;
    Q.ParamByName('ENT').AsInteger := GC_ENTREPRISE;
    Q.ParamByName('DOS').AsInteger := GC_DOSSIER;
    Q.ParamByName('ANN').AsInteger := GC_ANNEE;
    Q.ParamByName('MOS').AsInteger := GC_MOIS;
    Q.ParamByName('DOC').AsString  := ADocument;
    Q.Open;

    if Q.IsEmpty then
      raise Exception.CreateFmt(
        'GO_CHRONO : ligne manquante pour DOCUMENT=''%s'' ' +
        '(ENTREPRISE=-1, DOSSIER=-1, ANNEE=-1, MOIS=-1)', [ADocument]);

    LCurrent := Q.Fields[0].AsInteger;
    Q.Close;

    Result := LCurrent + 1;

    // Écriture de la nouvelle valeur
    Q.SQL.Text := SQL_CHRONO_UPDATE;
    Q.ParamByName('NEW_CHRONO').AsInteger := Result;
    Q.ParamByName('ENT').AsInteger        := GC_ENTREPRISE;
    Q.ParamByName('DOS').AsInteger        := GC_DOSSIER;
    Q.ParamByName('ANN').AsInteger        := GC_ANNEE;
    Q.ParamByName('MOS').AsInteger        := GC_MOIS;
    Q.ParamByName('DOC').AsString         := ADocument;
    Q.ExecSQL;

  finally
    Q.Free;
  end;
end;

end.
