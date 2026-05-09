unit ImportTypes;

{$SCOPEDENUMS ON}

interface

type
  TLogLevel = (Info, Warning, Error);

  TImportStats = record
    Inserted : Integer;
    Updated  : Integer;
    Skipped  : Integer;
    Errors   : Integer;
    procedure Reset;
    function  Summary: string;
  end;

implementation

uses System.SysUtils;

procedure TImportStats.Reset;
begin
  Inserted := 0; Updated := 0; Skipped := 0; Errors := 0;
end;

function TImportStats.Summary: string;
begin
  Result := Format('Insérés: %d | MàJ: %d | Ignorés: %d | Erreurs: %d',
    [Inserted, Updated, Skipped, Errors]);
end;

end.
