`TernaryOperatorSpacesFixer` incompatible with nullable constructor property promotion
## Bug report

After upgrading to PHP8 I have problems with CS Fixer. `TernaryOperatorSpacesFixer` inserts space after `?` that marks nullable arguments in constructors with property promotion:

```diff
--- Original
+++ New
@@ -7,7 +7,7 @@
 class Foo
 {
     public function __construct(
-        private ?string $foo = null,
+        private ? string $foo = null,
     ) {
         is_null(true ? '...' : null);
     }
```

### Code snippet that reproduces the problem

```php
<?php

class Foo
{
    public function __construct(
        private ?string $foo = null,
    ) {
        is_null(true ? '...' : null);
    }
}
```

**NOTE**: Ternary operator used anywhere in the class triggers this invalid change. Without actual ternary in the code, constructor is not touched. Without property promotion it works properly too.
