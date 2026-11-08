Support for object initialisation in `fully_qualified_strict_types`
## Rule request

`fully_qualified_strict_types` should shorten FQCN to imported symbols in `new \Foo\Bar()`-like cases.

### Code snippet that shows how the rule would fix PHP code

```diff
<?php

use Foo\Bar;
use Some\CustomException;

-$a = new \Foo\Bar();
+$a = new Bar();

-throw new \Some\CustomException('ohoh');
+throw new CustomException('ohoh');
```
Support for shortening FQCN for trait usage
```diff
<?php

use Bar\Baz;

class Foo {
-    use \Bar\Baz;
+    use Baz;
}
```

_Originally posted by @mvorisek in https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/pull/7459#discussion_r1403177320_

### Additional contract requirements

- When a `new` expression uses a fully qualified class name from the current namespace, shorten it to the unqualified name. For example, transform `<?php namespace B; new \B\A();` to `<?php namespace B; new A();`.
