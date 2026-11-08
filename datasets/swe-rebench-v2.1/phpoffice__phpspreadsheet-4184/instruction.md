Invalid HTML due to readEnding failure.
This is:

```
- [X] a bug report
- [ ] a feature request
- [ ] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)
```

### What is the expected behavior?
The HTML is valid and is able to find the end which is nothing more than a > symbol

### What is the current behavior?
Due to size of the file returned from filesize() the fseek is returning no data which causes it to fail. This appears to be due to using the same filename for loadingIntoExisting. The filesize reported is for the original version, but when it is updated with new data filesize does not report the new size.

### What are the steps to reproduce?
Try to use loadIntoExisting() on a smaller HTML file (in this case the OS is reporting 1,518 bytes, 4k on disk). Filesize returns 19792 as the size and then tries to seek to the offset based off of the sample size (19792 - 2048) which goes past the end of the file.


Please provide a [Minimal, Complete, and Verifiable example](https://stackoverflow.com/help/mcve) of code that exhibits the issue without relying on an external Excel file or a web server:

```php
<?php

require __DIR__ . '/vendor/autoload.php';

// Create new Spreadsheet object
$spreadsheet = new \PhpOffice\PhpSpreadsheet\Spreadsheet();

// add code that show the issue here...
                $reader = new \PhpOffice\PhpSpreadsheet\Reader\Html;
                $reader->setSheetIndex($index);
                $reader->loadIntoExisting('/tmp/smallhtml'. $spreadsheet);
```


### Which versions of PhpSpreadsheet and PHP are affected?
Php 7.1.29 / PhpSpreadsheet 1.8
