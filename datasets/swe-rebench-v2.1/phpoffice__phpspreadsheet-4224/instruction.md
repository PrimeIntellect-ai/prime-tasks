Add support for <s> tag when converting HTML to RichText
This is:

```
- [ ] a bug report
- [x] a feature request
- [x] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)
```

### What is the expected behavior?

`<s>` tag should be interpreted as strikethrough text, similar to the `<del>` tag.

### What is the current behavior?

Text inside `<s>` tag is displayed as normal text.

### What are the steps to reproduce?

```php
<?php

require __DIR__.'vendor/autoload.php';

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;

$spreadsheet = new Spreadsheet();
$activeWorksheet = $spreadsheet->getActiveSheet();
$input = 'Hello <s>test</s>world';
$html = new Html();
$richText = $html->toRichTextObject($input);
$activeWorksheet->setCellValue('A1', $richText);

$writer = new Xlsx($spreadsheet);
$writer->save('hello_world.xlsx');
```

### What features do you think are causing the issue

- [ ] Reader
- [ ] Writer
- [ ] Styles
- [ ] Data Validations
- [ ] Formula Calculations
- [ ] Charts
- [ ] AutoFilter
- [ ] Form Elements

### Does an issue affect all spreadsheet file formats? If not, which formats are affected?

All formats affected

### Which versions of PhpSpreadsheet and PHP are affected?

All versions
