v3.7.0 binary_operator_spaces and elseif
## Bug report

PHP CS Fixer 3.7.0 #StandWithUkraine️ by Fabien Potencier and Dariusz Ruminski.
PHP runtime: 8.0.15

```diff
$ tools/php-cs-fixer/vendor/bin/php-cs-fixer fix src --diff -vvv
PHP CS Fixer 3.7.0 #StandWithUkraine️ by Fabien Potencier and Dariusz Ruminski.
PHP runtime: 8.0.15
Loaded config default from "/Users/kenji/work/tmp/php-cs-fixer-test/.php-cs-fixer.php".
Using cache file ".php-cs-fixer.cache".
Paths from configuration file have been overridden by paths provided as command arguments.
F                                                                                                                      1 / 1 (100%)
Legend: ?-unknown, I-invalid file syntax (file ignored), S-skipped (cached or empty file), .-no changes, F-fixed, E-error
   1) src/test.php (blank_line_after_opening_tag, binary_operator_spaces)
      ---------- begin diff ----------
--- /Users/kenji/work/tmp/php-cs-fixer-test/src/test.php
+++ /Users/kenji/work/tmp/php-cs-fixer-test/src/test.php
@@ -1,7 +1,8 @@
 <?php
+
 $array = [];
 if (($c = count($array)) > 100) {
-    $_data = '100+';
+    $_data    = '100+';
 } elseif (($c = count($array)) > 0) {
-    $_data = '0+';
+    $_data    = '0+';
 }

      ----------- end diff -----------


Fixed all files in 0.046 seconds, 12.000 MB memory used
```

```php
<?php
$finder = PhpCsFixer\Finder::create()
    ->exclude('somedir')
    ->notPath('src/Symfony/Component/Translation/Tests/fixtures/resources.php')
    ->in(__DIR__)
;
$config = new PhpCsFixer\Config();
return $config->setRules([
        '@PSR12' => true,
        'binary_operator_spaces' => [
            'operators' => [
                '='  => 'align_single_space_minimal',
            ],
        ],
    ])
    ->setFinder($finder)
;
```

### Code snippet that reproduces the problem

```php
<?php
$array = [];
if (($c = count($array)) > 100) {
    $_data = '100+';
} elseif (($c = count($array)) > 0) {
    $_data = '0+';
}
```
