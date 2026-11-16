[Bug] Is this a typo?
class: `\PhpOffice\PhpSpreadsheet\Style\Style`

file: `phpoffice\phpspreadsheet\src\PhpSpreadsheet\Style\Style.php`

function: `exportArray1`

Is this a typo in:
```php
<?php
...
    [HIDDEN]
```

Should it be `[HIDDEN]`?

### Additional contract requirements

- The exported style array must expose the quote-prefix setting under the correctly spelled `quotePrefix` key.
