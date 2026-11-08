Unsupported operand types: string + string in date format (PHP 8.x)
This is:

```
- [X ] a bug report
- [ ] a feature request
- [ ] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)
```

### What is the expected behavior?
[HIDDEN]


### What is the current behavior?
string+string is an issue in PHP 8.x
Fatal error: Uncaught TypeError: Unsupported operand types: string + string in C:\Program Files\EasyPHP-Devserver-17\eds-www\aplitec\includes\modules\phpoffice\phpspreadsheet\src\PhpSpreadsheet\Calculation\TextData\Format.php:132
### What are the steps to reproduce?

<?php
require __DIR__ . '/vendor/autoload.php';
	$excelfile = 'BUG_PHPSpreadsheet_PHP8_DATE.xlsx';
  	$showPHPExcel = \PhpOffice\PhpSpreadsheet\IOFactory::load($excelfile);

	$liassewriter = \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($showPHPExcel, "Xlsx");
	$liassewriter->save("crash.xlsx");
?>
If this is an issue with reading a specific spreadsheet file, then it may be appropriate to provide a sample file that demonstrates the problem; but please keep it as small as possible, and sanitize any confidential information before uploading.

### What features do you think are causing the issue

- [ ] Reader
- [ X] Writer
- [ ] Styles
- [ ] Data Validations
- [ ] Formula Calculations
- [ ] Charts
- [ ] AutoFilter
- [ ] Form Elements

### Does an issue affect all spreadsheet file formats? If not, which formats are affected?

DATE Cell formatting when date cell is still a keyword and not yet a valid date!

### Which versions of PhpSpreadsheet and PHP are affected? PHP >= 8.0
[BUG_PHPSpreadsheet_PHP8_DATE.xlsx](https://github.com/user-attachments/files/17961714/BUG_PHPSpreadsheet_PHP8_DATE.xlsx)

### Additional contract requirements

- When formatting `May 2, 1952 3:54 p` with `yyyy-mm-dd hh:mm`, the result must be `1952-05-02 15:54`.
- When formatting `January 23, 1951` with `yyyy-mm-dd hh:mm`, the result must be `1951-01-23 00:00`.
- When formatting `3:54 May 2, 1952` with `yyyy-mm-dd hh:mm`, the result must be `1952-05-02 03:54`.
- If date/time formatting cannot interpret the input as a date or time, it must return the original input unchanged without raising a type error.
- Saving a workbook as XLSX must complete when a cell formula applies date/time formatting to an unparseable text value.
- Numeric Excel date serials, including numeric strings, must retain standard date/time number-format behavior.
