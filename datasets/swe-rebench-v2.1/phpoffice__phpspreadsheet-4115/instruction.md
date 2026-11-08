Bug in "Trunc" class
This is:

```
- [X] a bug report
- [ ] a feature request
- [ ] **not** a usage question (ask them on https://stackoverflow.com/questions/tagged/phpspreadsheet or https://gitter.im/PHPOffice/PhpSpreadsheet)
```

### What is the expected behavior?

PhpOffice\PhpSpreadsheet\Calculation\MathTrig\Trunc::evaluate(1.01, 1);  // expected: 1.0

### What is the current behavior?

PhpOffice\PhpSpreadsheet\Calculation\MathTrig\Trunc::evaluate(1.01, 1);  // current: 1.01

### What are the steps to reproduce?

```php
<?php

require __DIR__ . '/vendor/autoload.php';

echo PhpOffice\PhpSpreadsheet\Calculation\MathTrig\Trunc::evaluate(1.01, 1);

```
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

Formats that use formulas.

### Which versions of PhpSpreadsheet and PHP are affected?

All?
