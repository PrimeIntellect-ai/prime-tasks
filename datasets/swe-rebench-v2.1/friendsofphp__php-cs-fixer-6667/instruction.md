`braces` fixer adds unnecessary empty lines in files where code doesn't start at offset 0
## Bug report

given a file where code doesn't start at offset 0 (which is bad, I know), cs-fixer recently started  (through the `braces` fixer) adding random empty lines to the file in front of each indented statement.

If I manually fix the indent, the problem disappears.

### Code snippet that reproduces the problem

```php
<?php

    function foo()
    {
    }
```

running cs-fixer with just the `braces` fixer enabled will produce the following diff

```diff
   1) /path/to/test.php (braces)
      ---------- begin diff ----------
--- /path/to/test.php
+++ /path/to/test.php
@@ -1,5 +1,6 @@
 <?php

+
     function foo()
     {
     }

      ----------- end diff -----------
```

if I remove the 4 space indent at the beginning of all lines, the empty line will not be added.

Also, I can't quite reproduce it yet, but sometimes after making unrelated changes to the file, *another* empty line will be added.
