unit ImportContext;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils, System.Generics.Collections,
  FireDAC.Comp.Client,
  ImportTypes, ImportLog;

type
  // Dictionnaire clé-Excel (string) → ID base (integer) pour une entité donnée
  TKeyMap = TDictionary<string, Integer>;

  TImportContext = class
  private
    FConnection: TFDConnection;
    FLog       : TImportLog;
    // Nom-entité → son TKeyMap  (ex: 'Fournisseur', 'Client', ...)
    FKeyMaps   : TObjectDictionary<string, TKeyMap>;
    function GetOrCreateMap(const AEntity: string): TKeyMap;
  public
    constructor Create(AConnection: TFDConnection; ALog: TImportLog);
    destructor  Destroy; override;

    // Après chaque INSERT : enregistre le mapping clé-Excel → ID base
    procedure RegisterKey(const AEntity, AExcelKey: string; ADbId: Integer);

    // Avant chaque écriture de FK : résout clé-Excel → ID base (-1 si absent)
    function ResolveKey(const AEntity, AExcelKey: string): Integer;

    // Vrai si la clé a déjà été traitée (détection doublons)
    function KeyExists(const AEntity, AExcelKey: string): Boolean;

    property Connection: TFDConnection read FConnection;
    property Log       : TImportLog   read FLog;
  end;

implementation

constructor TImportContext.Create(AConnection: TFDConnection; ALog: TImportLog);
begin
  inherited Create;
  FConnection := AConnection;
  FLog        := ALog;
  FKeyMaps    := TObjectDictionary<string, TKeyMap>.Create([doOwnsValues]);
end;

destructor TImportContext.Destroy;
begin
  FKeyMaps.Free;
  inherited;
end;

function TImportContext.GetOrCreateMap(const AEntity: string): TKeyMap;
begin
  if not FKeyMaps.TryGetValue(AEntity, Result) then
  begin
    Result := TKeyMap.Create;
    FKeyMaps.Add(AEntity, Result);
  end;
end;

procedure TImportContext.RegisterKey(const AEntity, AExcelKey: string; ADbId: Integer);
begin
  GetOrCreateMap(AEntity).AddOrSetValue(AExcelKey, ADbId);
end;

function TImportContext.ResolveKey(const AEntity, AExcelKey: string): Integer;
var
  LMap: TKeyMap;
begin
  Result := -1;
  if (AExcelKey = '') then Exit;
  if FKeyMaps.TryGetValue(AEntity, LMap) then
    LMap.TryGetValue(AExcelKey, Result);
end;

function TImportContext.KeyExists(const AEntity, AExcelKey: string): Boolean;
var
  LMap: TKeyMap;
begin
  Result := FKeyMaps.TryGetValue(AEntity, LMap) and LMap.ContainsKey(AExcelKey);
end;

end.
