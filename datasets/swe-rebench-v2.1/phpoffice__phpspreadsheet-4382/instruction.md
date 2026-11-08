The COUNTIF function crashes PhpSpreadsheet if there is a #REF! error in the range argument.
First of all, let it be made clear this is low-priority, such errors are correctable in-workbook to not make the application crash anymore. This bug report is made only with feature parity in mind.

### This is:

- [X] a bug report
- [ ] a feature request
- [X] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)

### What is the expected behavior?

The COUNTIF function fails gracefully and returns "#REF!" too.

### What is the current behavior?

Err. 500 with message:
```
AH01071: Got error 'PHP message: PHP Fatal error:  Uncaught TypeError: PhpOffice\\PhpSpreadsheet\\Calculation\\Statistical\\Conditional::COUNTIF(): Argument #1 ($range) must be of type array, string given in .../phpoffice/phpspreadsheet/src/PhpSpreadsheet/Calculation/Statistical/Conditional.php:82
Stack trace:
#0 [internal function]: PhpOffice\\PhpSpreadsheet\\Calculation\\Statistical\\Conditional::COUNTIF()
#1 .../phpoffice/phpspreadsheet/src/PhpSpreadsheet/Calculation/Calculation.php(5163): call_user_func_array()
#2 .../phpoffice/phpspreadsheet/src/PhpSpreadsheet/Calculation/Calculation.php(3743): PhpOffice\\PhpSpreadsheet\\Calculation\\Calculation->processTokenStack()
#3 .../phpoffice/phpspreadsheet/src/PhpSpreadsheet/Calculation/Calculation.php(3543): PhpOffice\\PhpSpreadsheet\\Calculation\\Calculation->_calculateFormulaValue()
#4 .../phpoffice/phpspreadsheet/src/PhpSpreadsheet/Cell/Cell.php(428): PhpOffice\\PhpSpreadsheet\\C...
```

### What are the steps to reproduce?

```php
$filePath='REF in COUNTIF.xlsx';

$reader = IOFactory::createReader('Xlsx');
$spreadsheet = $reader->load($filePath);
echo $spreadsheet->getSheet(1)->getCell("A1")->getCalculatedValue();
```

Here is an Excel file to reproduce this behavior with: [REF in COUNTIF.xlsx](https://github.com/user-attachments/files/18944434/REF.in.COUNTIF.xlsx)

There are probably more issues regarding errored-out range inputs in COUNTIF.

### What features do you think are causing the issue

- [ ] Reader
- [ ] Writer
- [ ] Styles
- [ ] Data Validations
- [X] Formula Calculations
- [ ] Charts
- [ ] AutoFilter
- [ ] Form Elements

### Does an issue affect all spreadsheet file formats? If not, which formats are affected?

Not tested, but probably.

### Which versions of PhpSpreadSheet and PHP are affected?

PhpSpreadSheet: 4.0.0
PHP: 8.1
