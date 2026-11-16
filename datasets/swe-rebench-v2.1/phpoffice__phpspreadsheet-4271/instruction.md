"forceFullCalc" is not necessary in current Excel
This is:

```
- [x] a bug report
- [ ] a feature request
- [ ] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)
```

### What is the expected behavior?

If I create a file in PhpSpreadsheet without calculating it (`setPreCalculateFormulas(false)`), when I open it in excel it will calculate automatically and I'm hoping there won't be a "Calculate" button.

https://github.com/PHPOffice/PhpSpreadsheet/blob/b35de99c1600f58940d33221810b187d53745dc1/src/PhpSpreadsheet/Writer/Xlsx/Workbook.php#L163

I wasn't able to trace the reason why "forceFullCalc" was added, but it wasn't there in the PHPExcel era.
Since "calcMode" is output as "auto", I think it's correct that "Calculate" is not displayed.

### What is the current behavior?

When you open the created file in Excel, it will be `Calculate` (manual recalculation).
![image](https://github.com/user-attachments/assets/a95cbffc-d68b-447b-85fe-262d4b4d8349)

### What are the steps to reproduce?

Please provide a [Minimal, Complete, and Verifiable example](https://stackoverflow.com/help/mcve) of code that exhibits the issue without relying on an external Excel file or a web server:

```php
<?php

require __DIR__ . '/vendor/autoload.php';

// Create new Spreadsheet object
$spreadsheet = new \PhpOffice\PhpSpreadsheet\Spreadsheet();

// add code that show the issue here...
$sheet = $spreadsheet->getActiveSheet();
$sheet->setCellValue('A1', '=1+1');
$writer = \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($spreadsheet, \PhpOffice\PhpSpreadsheet\IOFactory::WRITER_XLSX);
$writer->setPreCalculateFormulas(false);
$writer->save(__DIR__ . '/sample.xlsx');
```

Open the file you created in Excel.

If this is an issue with reading a specific spreadsheet file, then it may be appropriate to provide a sample file that demonstrates the problem; but please keep it as small as possible, and sanitize any confidential information before uploading.

- [sample.original.xlsx](https://github.com/user-attachments/files/18070277/sample.original.xlsx)
- [sample.remove-forceFullCalc.xlsx](https://github.com/user-attachments/files/18070356/sample.remove-forceFullCalc.xlsx)

### What features do you think are causing the issue

- [ ] Reader
- [x] Writer
- [ ] Styles
- [ ] Data Validations
- [ ] Formula Calculations
- [ ] Charts
- [ ] AutoFilter
- [ ] Form Elements

### Does an issue affect all spreadsheet file formats? If not, which formats are affected?

xlsx ( & xlsm )

### Which versions of PhpSpreadsheet and PHP are affected?

PhpSpreadsheet: 3.6.0
PHP: 8.2.13
Excel: Office 2019 & Office365

### Additional contract requirements

- The Xlsx writer exposes `setForceFullCalc(?bool $forceFullCalc): self`. It returns the same Xlsx writer instance, so calls can be chained.
- The value is written into `xl/workbook.xml` as the `forceFullCalc` attribute of the `calcPr` element: `1` when the option is `true` and `0` when it is `false`.
- When `forceFullCalc` is `null` (the default), the writer uses the opposite of the current pre-calculate-formulas setting: `1` when `setPreCalculateFormulas(false)` was used and `0` when `setPreCalculateFormulas(true)` was used. This preserves the existing behaviour, so a caller that wants to suppress the "Calculate" button when formulas are not pre-calculated must explicitly call `setForceFullCalc(false)`.
- The `calcPr` element continues to be written with `calcMode="auto"`.
