braces: Incorrect closing brace for switch where last case contains only a comment
## Bug report

PHP-CS-Fixer incorrectly unindents the comment and indents the closing brace of a switch when the last case only contains a comment.

```
PHP CS Fixer 3.9.4 (093466b) Grand Awaiting by Fabien Potencier and Dariusz Ruminski.
PHP runtime: 8.0.21
Loaded config default.
Using cache file ".php-cs-fixer.cache".
F                                                                                                                                                                                                      1 / 1 (100%)
Legend: ?-unknown, I-invalid file syntax (file ignored), S-skipped (cached or empty file), .-no changes, F-fixed, E-error
```
```diff
   1) test.php (braces)
      ---------- begin diff ----------
--- /pwd/test.php
+++ /pwd/test.php
@@ -5,5 +5,5 @@
         echo "Okay", PHP_EOL;
         break;
     case 'baz':
-        // Nothing to do
-}
+    // Nothing to do
+    }

      ----------- end diff -----------


Checked all files in 0.011 seconds, 14.000 MB memory used
```

### Code snippet that reproduces the problem

```php
<?php

switch ($foo) {
    case 'bar':
        echo "Okay", PHP_EOL;
        break;
    case 'baz':
        // Nothing to do
}
```
