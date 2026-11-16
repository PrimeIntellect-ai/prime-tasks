PhpCsFixer\Fixer\Phpdoc\PhpdocVarWithoutNameFixer removes only the first variable name
## Bug report
PHP version: 7.4
PHP CS Fixer 2.17.3 Desert Beast by Fabien Potencier and Dariusz Ruminski

Run via `https://github.com/symplify/easy-coding-standard`

Console output:
``` bash
13) FeedbackModalControl.php

    ---------- begin diff ----------
--- Original
+++ New
@@ -16,7 +16,7 @@
 {

     /**
-     * @var array<callable(string $feedback, FileUpload $screenshot): void>
+     * @var array<callable(string, FileUpload $screenshot): void>
      */
     public array $onSuccess = [];
    ----------- end diff -----------


Applied checkers:

 * PhpCsFixer\Fixer\Phpdoc\PhpdocVarWithoutNameFixer
```

Relevant source code:
```php
final class FeedbackModalControl extends Control
{

    /**
     * @var array<callable(string $feedback, FileUpload $screenshot): void>
     */
    public array $onSuccess = [];

}
```

Expected behavior:
Remove both variables.
