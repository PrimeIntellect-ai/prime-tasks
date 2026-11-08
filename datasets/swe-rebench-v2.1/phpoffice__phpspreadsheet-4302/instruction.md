cell values changed in a cloned ws reflect in the original one also
This is:

```
- [x] a bug report
- [ ] a feature request
```

### What is the expected behavior?

value in worksheet 'Condendes B' cell A1 is set as `=sum('Detailed B'!A1:A10)` and should remain that way

### What is the current behavior?

value in worksheet 'Condendes B' cell A1 is changes in `=sum('Detailed Total'!A1:A10)` after the worksheet object is cloned and cell A1 is changed in the cloned object

### What are the steps to reproduce?

Please provide a [Minimal, Complete, and Verifiable example](http://stackoverflow.com/help/mcve) of code that exhibits the issue without relying on an external Excel file or a web server:

```php
<?php

require_once 'vendor/autoload.php';

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;

$xlsx = new Spreadsheet();
$xlsx->removeSheetByIndex(0);

$availableWs = [];

// this are set to a sum of values from sheets we will created
// some line below
$worksheet = $xlsx->createSheet();
$worksheet->setTitle('Condensed A');
$worksheet->getCell("A1")->setValue("=sum('Detailed A'!A1:A10)");
$worksheet->getCell("A2")->setValue(rand(1, 30));
$availableWs[] = 'Condensed A';

$worksheet = $xlsx->createSheet();
$worksheet->setTitle('Condensed B');
$worksheet->getCell("A1")->setValue("=sum('Detailed B'!A1:A10)");
$worksheet->getCell("A2")->setValue(rand(1, 30));
$availableWs[] = 'Condensed B';

// at this point the value in worksheet 'Condendes B' cell A1 is
// =sum('Detailed B'!A1:A10)

// worksheet in question is cloned and totals are attached
$totalWs = clone $xlsx->getSheet($xlsx->getSheetCount() - 1);
$totalWs->setTitle('Condensed Total');
$formula = '=';
foreach ($availableWs as $ws) {
    $formula .= sprintf("+'%s'!A2", $ws);
}
$totalWs->getCell("A1")->setValue("=sum('Detailed Total'!A1:A10)");
$totalWs->getCell("A2")->setValue($formula);
$xlsx->addSheet($totalWs);

$availableWs = [];

$worksheet = $xlsx->createSheet();
$worksheet->setTitle('Detailed A');
for ($step = 1; $step <= 10; $step++) {
    $worksheet->getCell("A{$step}")->setValue(rand(1, 30));
}
$availableWs[] = 'Detailed A';

$worksheet = $xlsx->createSheet();
$worksheet->setTitle('Detailed B');
for ($step = 1; $step <= 10; $step++) {
    $worksheet->getCell("A{$step}")->setValue(rand(1, 30));
}
$availableWs[] = 'Detailed B';

$totalWs = clone $xlsx->getSheet($xlsx->getSheetCount() - 1);
$totalWs->setTitle('Detailed Total');

for ($step = 1; $step <= 10; $step++) {
    $formula = '=';
    foreach ($availableWs as $ws) {
        $formula .= sprintf("+'%s'!A%s", $ws, $step);
    }
    $totalWs->getCell("A{$step}")->setValue($formula);
}
$xlsx->addSheet($totalWs);

// the value in worksheet 'Condendes B' cell A1 is
// =sum('Detailed Total'!A1:A10)

$writer = new Xlsx($xlsx);
$writer->save('hello world.xlsx');
```


### Which versions of PhpSpreadsheet and PHP are affected?
1.4
php 7.2.6 win & linux
