[3.0 dev] `phpdoc_types_order` does not work together with array shapes
## Bug report

### Code snippet that reproduces the problem

```php
    /**
     * @return array<array{level:string, message:string, context:array<mixed>}>
     */
    public function getLogs(?string $level = null) : array
    {
    }
```

```
PHP CS Fixer 3.0.1-DEV Constitution by Fabien Potencier and Dariusz Ruminski
Runtime: PHP 8.0.7
Loaded config default from "/Volumes/CS/www/website/.php-cs-fixer.php".
Using cache file "var/.php_cs.cache".
Paths from configuration file have been overridden by paths provided as command arguments.
F                                                                                                                            1 / 1 (100%)
Legend: ?-unknown, I-invalid file syntax (file ignored), S-skipped (cached or empty file), .-no changes, F-fixed, E-error
   1) /Volumes/CS/www/website/src-dev/Testing/Logging/InMemorLogger.php (phpdoc_types_order)
      ---------- begin diff ----------
--- /Volumes/CS/www/website/src-dev/Testing/Logging/InMemorLogger.php
+++ /Volumes/CS/www/website/src-dev/Testing/Logging/InMemorLogger.php
@@ -97,7 +97,7 @@
     }

     /**
-     * @return array<array{level:string, message:string, context:array<mixed>}>
+     * @return array<array{level:string, message:string, context:array<mixed>|}>
      */
     public function getLogs(?string $level = null) : array
     {

      ----------- end diff -----------


Checked all files in 0.085 seconds, 18.000 MB memory used
exit status 8
```
