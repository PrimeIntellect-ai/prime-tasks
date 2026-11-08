binary_operator_spaces adding whitespace around hyphen outside php block
## Bug report

PHP-CS-Fixer is incorrectly treating hyphens outside PHP block in my template files as Subtraction operator and adding whitespace around it.

#### Version Info
```
$ php-cs-fixer -V
PHP CS Fixer 3.8.0 (cbad111) BerSzcz against war! by Fabien Potencier and Dariusz Ruminski.
PHP runtime: 8.1.7
```

#### Reproducable Example
```php
<?php
// test.php
$id = 1;
$path = 'test';
?>

<a href="test-<?=$path?>-<?=$id?>.html">Test</a>
```

```php
<?php
// .php-cs-fixer.dist.php

// for more info see:
// https://github.com/FriendsOfPHP/PHP-CS-Fixer#usage
// https://github.com/FriendsOfPHP/PHP-CS-Fixer/blob/master/UPGRADE.md

$finder = PhpCsFixer\Finder::create()
    ->in(__DIR__)
;

return (new PhpCsFixer\Config())
    ->setRules([
        'binary_operator_spaces' => true,
    ])
    ->setLineEnding("\n")
    ->setFinder($finder)
;
```


```diff
php-cs-fixer fix --dry-run --diff test.php                                                                     ⎈ docker-desktop 13:58:24
Loaded config default from "/private/tmp/test/.php-cs-fixer.dist.php".
Using cache file ".php-cs-fixer.cache".
Paths from configuration file have been overridden by paths provided as command arguments.
   1) test.php
      ---------- begin diff ----------
--- /private/tmp/test/test.php
+++ /private/tmp/test/test.php
@@ -3,4 +3,4 @@
 $path = 'test';
 ?>

-<a href="test-<?=$path?>-<?=$id?>.html">Test</a>
+<a href="test-<?=$path?> - <?=$id?>.html">Test</a>

      ----------- end diff -----------
```

#### Expected Output

PHP-CS-Fixer should not modify content outside PHP block.

<!--
  Before reporting a bug, make sure PHP CS Fixer is up-to-date.

  Please describe the problem and provide technical details such as:
   * PHP CS Fixer version and PHP runtime: php-cs-fixer -V
   * the command used to run PHP CS Fixer (run with `-vvv`)
   * the configuration (file) you used
-->

### Code snippet that reproduces the problem

<!--
  Provide a minimal code snippet before running PHP CS Fixer. If relevant,
  also provide the expected output, the actual output and/or the error that
  occurred, if any.

  Please use markdown syntax for each code snippet, e.g.:

  ```php
  <?php
  $var = 'foo';
  ```
-->
