Removing columns containing merged columns
This is:

- [X] a bug report
- [ ] a feature request
- [ ] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)

### What is the expected behavior?
The columns are not correctly removed and the file need to be repaired in Excel
<img width="292" alt="expected" src="https://user-images.githubusercontent.com/1458015/33539106-22930f68-d8de-11e7-8357-6a205974e4ef.png">


### What is the current behavior?
After the repair
<img width="350" alt="result" src="https://user-images.githubusercontent.com/1458015/33539105-225a3260-d8de-11e7-8427-1807ff830a05.png">

### What are the steps to reproduce?
Initial template:
<img width="617" alt="template" src="https://user-images.githubusercontent.com/1458015/33539149-599bf024-d8de-11e7-8df7-8aa55147a4c5.png">
The excel file: [TestMergedColumns.xlsx](https://github.com/PHPOffice/PhpSpreadsheet/files/1525901/TestMergedColumns.xlsx)

```php
<?php

require __DIR__ . '/vendor/autoload.php';

// Create new Spreadsheet object
$reader = \PhpOffice\PhpSpreadsheet\IOFactory::createReader('Xlsx');
$spreadsheet = $reader->load('/tmp/TestMergedColumns.xlsx');
$worksheet = $spreadsheet->getSheetByName('Sheet1');

// Remove 5 columns (from B to F)
$worksheet->removeColumnByIndex(2, 5);
$writer = \PhpOffice\PhpSpreadsheet\IOFactory::createWriter($spreadsheet, 'Xlsx');
$writer->save('/tmp/result.xlsx');
```


### Which versions of PhpSpreadsheet and PHP are affected?
- Commit: 59326f1064d61a6ff77822b64124a8046e06a46d
