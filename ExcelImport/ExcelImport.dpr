program ExcelImport;

uses
  Vcl.Forms,
  MainForm in 'Forms\MainForm.pas' {FormMain},
  ImportTypes in 'Core\ImportTypes.pas',
  ImportLog in 'Core\ImportLog.pas',
  ExcelReader in 'Core\ExcelReader.pas',
  DbHelpers in 'Core\DbHelpers.pas',
  BaseImporter in 'Core\BaseImporter.pas',
  ImportOrchestrator in 'Importers\ImportOrchestrator.pas',
  ImportEngagements in 'Importers\ImportEngagements.pas',
  ImportContext in 'Core\ImportContext.pas';

// ImportMarches        in 'Importers\ImportMarches.pas',
  // ImportAccordsCadres  in 'Importers\ImportAccordsCadres.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
