program ExcelImport;

uses
  Vcl.Forms,
  Forms\MainForm       in 'Forms\MainForm.pas'      {FormMain},
  Core\ImportTypes     in 'Core\ImportTypes.pas',
  Core\ImportLog       in 'Core\ImportLog.pas',
  Core\ImportContext   in 'Core\ImportContext.pas',
  Core\ExcelReader     in 'Core\ExcelReader.pas',
  Core\DbHelpers       in 'Core\DbHelpers.pas',
  Core\BaseImporter    in 'Core\BaseImporter.pas',
  Importers\ImportOrchestrator   in 'Importers\ImportOrchestrator.pas',
  Importers\ImportEngagements    in 'Importers\ImportEngagements.pas';
  // Importers\ImportMarches      in 'Importers\ImportMarches.pas',
  // Importers\ImportAccordsCadres in 'Importers\ImportAccordsCadres.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
