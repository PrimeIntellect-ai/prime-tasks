Error open file Xlsx when modify value
Good morning,

Since switching to version >= 2.2, the "setCellValue" method causes an error when opening Excel.
The error is : "We found a problem in the content of XXX, but we can try to recover as much content as possible.".
It only produces this with the "Xlsx" format. I tried to reproduce the error with minimal code. But, if you open the file and save without modifying a single line, the file opens correctly.

The function "error_reporting(E_ALL)" gives no error.

Thank you so much



This is:

```
- [ X] a bug report
- [ ] a feature request
- [ ] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)
```

### What are the steps to reproduce?
Execute the code

Please provide a [Minimal, Complete, and Verifiable example](https://stackoverflow.com/help/mcve) of code that exhibits the issue without relying on an external Excel file or a web server:

```php
<?php
require __DIR__ . '/vendor/autoload.php';

$spreadsheet = new \PhpOffice\PhpSpreadsheet\Spreadsheet();
$spreadsheet->getActiveSheet()->setCellValue('D1', 'MyDate');

$path = __DIR__.'/file_example.xlsx';
$writer = IOFactory::createWriter($spreadsheet, 'Xlsx');
$writer->save($path);
?>

// add code that show the issue here...
```
If this is an issue with reading a specific spreadsheet file, then it may be appropriate to provide a sample file that demonstrates the problem; but please keep it as small as possible, and sanitize any confidential information before uploading.
[file_example.xlsx](https://github.com/user-attachments/files/16507655/file_example.xlsx)
![error excel open](https://github.com/user-attachments/assets/8644e9f9-5354-463b-9d37-d18a7810dc00)



### What features do you think are causing the issue
- [ ] Reader
- [ X] Writer
- [ ] Styles
- [ ] Data Validations
- [ ] Formula Calculations
- [ ] Charts
- [ ] AutoFilter
- [ ] Form Elements

### Which versions of PhpSpreadsheet and PHP are affected?
Phpspreasheet >=2.2
PHP >= 8.1
Excel 2016
Environment Windows
Langue French

### Additional contract requirements

- Setting a cell value must not change the sheet's active cell or its selected cells; after `setCellValue('D1', 'MyDate')` on a new sheet, the active cell and selected cells still report their original values (`A1`).
- The saved Xlsx file must record the same active cell in its sheet view selection, so the file opens in Excel without the content-recovery warning.
