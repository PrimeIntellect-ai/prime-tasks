Braces rule: Omitting "break" in switch incorrectly indents closing brace
## Bug report

Adding another test case for incorrect indentation, adding to #6470.

PHP CS Fixer 3.9.5 Grand Awaiting by Fabien Potencier and Dariusz Ruminski.
PHP runtime: 7.4.30

Command:
php-cs-fixer fix -vvv --rules=braces testcase.php

### Code snippet that reproduces the problem

This code snippet should not be changed:

```php
<?php

function foo($var)
{
    switch ($var) {
        case 'one':
            break;
        case 'two':
            break;
        default:
    }
}

switch ($var) {
    case 'one':
        break;
    case 'two':
        break;
    default:
}
```

Version 3.9.5 is indenting the closing brace of the switch statement one level too far.
