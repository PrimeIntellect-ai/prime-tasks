Bug in `static_lambda` rule
Hi,

It looks like the `static_lambda` rule is not working correctly in this case. Even if the case is totally unlikely to happen, it should not add the `static` keyword in the front.

```php
<?php

declare(strict_types=1);

namespace App;

class Foo
{
    public function foo()
    {
        return array_map(
            fn ($item) => $this,
            []
        );
    }
}

Current result:

```
--- /home/devlin/Code/XXX/src/Foo.php
+++ /home/devlin/Code/XXX/src/Foo.php
@@ -1,5 +1,12 @@
 <?php

 declare(strict_types=1);

 namespace App;
@@ -9,7 +16,7 @@
     public function foo()
     {
         return array_map(
-            fn ($item) => $this,
+            static fn ($item) => $this,
             []
         );
     }
```

Expected result:

It should not add the `static` keyword.
