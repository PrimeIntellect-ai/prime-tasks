A mailto hyperlink emits the url text instead of the hyperlink in Html output
This is:

```
- [X] a bug report
- [ ] a feature request
- [ ] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)
```
Setting a mailto hyperlink on a cell replaces the cell contents with the mailto url when writing HTML.

[HIDDEN]

### What is the expected behavior?
Output:

<td class="column0 style0 s"><a href="mailto:me@example.com" title="">Mail Me!</a></td>

### What is the current behavior?
Outputs:

<td class="column0 style0 s">mailto:me@example.com</td>

### What are the steps to reproduce?

Please provide a [Minimal, Complete, and Verifiable example](https://stackoverflow.com/help/mcve) of code that exhibits the issue without relying on an external Excel file or a web server:

```php
<?php
require __DIR__ . '/vendor/autoload.php';

$spreadsheet = new \PhpOffice\PhpSpreadsheet\Spreadsheet();

$worksheet = $spreadsheet->getActiveSheet();

$worksheet->setCellValueByColumnAndRow(1, 1, 'Mail Me!');

$worksheet->getCell('A1')->getHyperlink()->setUrl('mailto:me@example.com');

$writer = PhpOffice\PhpSpreadsheet\IOFactory::createWriter($spreadsheet, 'Html');

$writer->save('php://output');
?>
```
If this is an issue with reading a specific spreadsheet file, then it may be appropriate to provide a sample file that demonstrates the problem; but please keep it as small as possible, and sanitize any confidential information before uploading.

### What features do you think are causing the issue

- [ ] Reader
- [X] Writer
- [ ] Styles
- [ ] Data Validations
- [ ] Formula Calculations
- [ ] Charts
- [ ] AutoFilter
- [ ] Form Elements

### Does an issue affect all spreadsheet file formats? If not, which formats are affected?
Only affects HTML output

### Which versions of PhpSpreadsheet and PHP are affected?
At least 1.28 onwards

### Additional contract requirements

- When an HTML writer renders a cell with a mailto hyperlink, render it as an anchor whose href is the mailto URL and whose link text is the cell contents; do not replace the cell contents with the URL.
- JavaScript hyperlinks must not be rendered as clickable anchors.
