NamespaceResolver does not correctly lookup namespace for properties in parent class
**Describe the bug**
I want to map a class which extends another class and has property with phpdoc (class).

```php
<?php
declare(strict_types = 1);

namespace Foo

use Foo\Model\BarModel

class test extends BarModel
{
}
```

```php
<?php
declare(strict_types = 1);

namespace Foo\Model

use Foo\MetaModel\Meta;

class BarModel
{
    /** @var null|Meta */
    public $meta;
}
```

```php
<?php

declare(strict_types = 1);

namespace Foo\MetaModel;

class Meta
{
    /** @var null|string */
    public $type;
}

```
The Namespaceresolver does not correct lookup the namespace of the used Foo\MetaModel\Meta.
Instead it will look only for Meta. Only a complete phpdoc helps here with Foo\MetaModel\Meta


PHP Version: 7.2
Json-Mapper: 2.9.0
Mode: (new JsonMapperFactory())->bestFit()
