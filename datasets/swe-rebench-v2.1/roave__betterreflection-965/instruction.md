`ReflectionFunctionAbstract` has incorrect `locatedSource` value
When trying to get the location of the method which is inherited from the parent class fails with the `InvalidNodePosition` exception, but from a deeper look, it seems that the `$this->locatedSource->getSource()` method returns not the parent class source but the source of which implemented it.

From looking around the code seems, like it should return [HIDDEN]

Reproducible code:
<details>
  <summary>Click to expand!</summary>

```php
<?php

declare(strict_types=1);

use Roave\BetterReflection\Reflection\ReflectionClass;
use Roave\BetterReflection\Reflection\ReflectionEnum;

require_once __DIR__ . '/vendor/autoload.php';

$classRef = ReflectionClass::createFromName(ReflectionEnum::class);
$methodRef = $classRef->getMethod('__toString');
$methodRef->getStartColumn();
```

</details>

### Additional contract requirements

A method obtained through a class other than the one where it was declared must expose the source of its declaring class or trait, rather than the source of the class through which it was obtained. Querying the location of an inherited method, including its start column, must complete without an `InvalidNodePosition` exception. A function reflection must continue to expose its own located source.
