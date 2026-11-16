`binary_operator_spaces` problem with several shifts in single line
## Bug report

<!--
  Before reporting a bug, make sure PHP CS Fixer is up-to-date.

  Please describe the problem and provide technical details such as:
   * PHP version: php -v
   * PHP CS Fixer version: php-cs-fixer -V
   * the command used to run PHP CS Fixer (run with `-vvv`)
   * the configuration (file) you used
-->

### Code snippet that reproduces the problem

file.php:
```php
<?php

$planPercent = $periodFilled['plan']/$maxPlan * 100;
$factPercent = $periodFilled['actual']/$maxPlan * 100;

```
.php_cs:
```php
<?php

$finder = PhpCsFixer\Finder::create()
    ->in(__DIR__)
;

return PhpCsFixer\Config::create()
    ->setFinder($finder)
    ->setRules([
        'binary_operator_spaces' => ['default' => 'align_single_space_minimal']
    ])
    ->setLineEnding("\n")
;

```
### Fixing
```
 php-cs-fixer fix -vvv file.php
PHP CS Fixer 2.18.5 Remote Void by Fabien Potencier and Dariusz Ruminski (e0f6d05)
Runtime: PHP 7.4.16
Loaded config default from "<masked>/.php_cs".
Using cache file ".php_cs.cache".
Paths from configuration file have been overridden by paths provided as command arguments.
F
Legend: ?-unknown, I-invalid file syntax (file ignored), S-skipped (cached or empty file), .-no changes, F-fixed, E-error
   1) file.php (binary_operator_spaces)

Fixed all files in 0.011 seconds, 12.000 MB memory used
```
#### Actual result
```
 cat file.php
<?php

$planPercent = $periodFilled['plan']   / $maxPlan   * 100;
$factPercent = $periodFilled['actual'] / $maxPlan * 100;
```

#### Expected result
```
 cat file.php
<?php

$planPercent = $periodFilled['plan']   / $maxPlan * 100;
$factPercent = $periodFilled['actual'] / $maxPlan * 100;
```
