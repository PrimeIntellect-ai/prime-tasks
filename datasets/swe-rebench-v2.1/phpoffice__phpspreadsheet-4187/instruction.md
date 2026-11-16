Html Entities in Excel 2003 File
This is:

```
- [x] a bug report
```
Not even sure if this is a bug report or a feature request as I could not find if this type of XLS file is supported.

### What is the expected behavior?
PhpSpreadsheet to read the file as I can open it just fine in OpenOffice.

### What is the current behavior?
Trying to read the file I get the error `The filename products.xls is not recognised as an OLE file` trying to read it as `Xls`. Trying to read it as `Xml` because the content is just XML, generates a lot of PHP warnings:
```
HP Warning:  simplexml_load_string(): Entity: line 1261: parser error : Entity 'iota' not defined in /vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Reader/Xml.php on line 120
PHP Warning:  simplexml_load_string(): &Omicron;&iota; &Kappa;ά&nu;&phi;&iota;&lambda;&nu;&tau; &kappa;&alpha;&iota; & in /vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Reader/Xml.php on line 120
PHP Warning:  simplexml_load_string():                                         ^ in /vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Reader/Xml.php on line 120
PHP Warning:  simplexml_load_string(): Entity: line 1261: parser error : Detected an entity reference loop in /vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Reader/Xml.php on line 120
PHP Warning:  simplexml_load_string(): &Omicron;&iota; &Kappa;ά&nu;&phi;&iota;&lambda;&nu;&tau; &kappa;&alpha;&iota; & in /vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Reader/Xml.php on line 120
PHP Warning:  simplexml_load_string():                                         ^ in /vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Reader/Xml.php on line 120
```

### What are the steps to reproduce?

The file used in this example:
[ProductsAPI-14-06-2021.xls](https://github.com/PHPOffice/PhpSpreadsheet/files/6647923/ProductsAPI-14-06-2021.xls)

Please provide a [Minimal, Complete, and Verifiable example](https://stackoverflow.com/help/mcve) of code that exhibits the issue without relying on an external Excel file or a web server:

This is trying to read it as XLS:
```php
<?php

use PhpOffice\PhpSpreadsheet\IOFactory;

require __DIR__ . '/vendor/autoload.php';
$reader        = IOFactory::createReader('Xls');
$reader->setLoadAllSheets();
$spreadsheet     = $reader->load('products.xls');

```

This is trying to read it as XML:
```php
<?php

use PhpOffice\PhpSpreadsheet\IOFactory;

require __DIR__ . '/vendor/autoload.php';
$reader        = IOFactory::createReader('Xml');
$reader->setLoadAllSheets();
$spreadsheet     = $reader->load('products.xls');

```

I have also tried it with this code:
```php
<?php

use PhpOffice\PhpSpreadsheet\IOFactory;

require __DIR__ . '/vendor/autoload.php';

$excel = IOFactory::load('products.xls');
```
That results in the same output as trying to read it as an XML file above.

### Which versions of PhpSpreadsheet and PHP are affected?
1.18.0
