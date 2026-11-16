allowSuperfluousKeys and union do not work together
Consider the following example:

```php
<?php

use CuyZ\Valinor\Mapper\Source\Source;
use CuyZ\Valinor\MapperBuilder;

require('vendor/autoload.php');

$payload = (new MapperBuilder())
    ->allowSuperfluousKeys()
    ->mapper()
    ->map(
        <<<'EOT'
            array {
                status: 200,
                foo: array {
                    bar: string,
                },
            } | array {
                status: 400,
                error: string,
            }
            EOT,
        Source::json(<<<'EOT'
                {
                    "status": 200,
                    "foo": {
                        "bar": "xxx"
                    }
                }
                EOT)
    );

var_dump($payload);
```

My schema is a partial API response, because I do not care about additional keys. This first example validates properly: There are no additional keys. However if I add one:

```php
<?php

use CuyZ\Valinor\Mapper\Source\Source;
use CuyZ\Valinor\MapperBuilder;

require('vendor/autoload.php');

$payload = (new MapperBuilder())
    ->allowSuperfluousKeys()
    ->mapper()
    ->map(
        <<<'EOT'
            array {
                status: 200,
                foo: array {
                    bar: string,
                },
            } | array {
                status: 400,
                error: string,
            }
            EOT,
        Source::json(<<<'EOT'
                {
                    "status": 200,
                    "foo": {
                        "bar": "xxx",
                        "yyy": "zzz"
                    }
                }
                EOT)
    );

var_dump($payload);
```

… the response fails to validate:

> Fatal error: Uncaught CuyZ\Valinor\Mapper\TypeTreeMapperError: Could not map type `array{status: 200, foo: array{bar: string}}|array{status: 400, error: string}`. An error occurred at path *root*: Value object(CuyZ\Valinor\Mapper\Source\Source) does not match any of `array{status: 200, foo: array{bar: string}}`, `array{status: 400, error: string}`. in /pwd/src/Mapper/TypeTreeMapper.php on line 29

It works properly if I remove the top-level union:

```php
<?php

use CuyZ\Valinor\Mapper\Source\Source;
use CuyZ\Valinor\MapperBuilder;

require('vendor/autoload.php');

$payload = (new MapperBuilder())
    ->allowSuperfluousKeys()
    ->mapper()
    ->map(
        <<<'EOT'
            array {
                status: 200,
                foo: array {
                    bar: string,
                },
            }
            EOT,
        Source::json(<<<'EOT'
                {
                    "status": 200,
                    "foo": {
                        "bar": "xxx",
                        "yyy": "zzz"
                    }
                }
                EOT)
    );

var_dump($payload);
```
Union of scalar and array of classes does not work
Hi, when trying to map union of scalar and array of classes, i get error:
```
CuyZ\Valinor\Mapper\TypeTreeMapperError: Could not map type `Foo`. An error occurred at path items: Invalid value array{0: array{…}}.
```
```php
(new MapperBuilder())->mapper()->map(Foo::class, Source::array([
    'items' => [
        [
            'id' => 1,
            'value' => 'baz',
        ],
    ],
]));
```

```php
readonly final class Foo
{
    public function __construct(
        /** @var string|list<Bar> */
        public string|array $items,
    ) {
    }
}
```

```php
readonly final class Bar
{
    public function __construct(
        public int $id,
        public string $value,
    ) {
    }
}
```

When trying as source the string value (first type of the union) it works as expected.
```php
(new MapperBuilder())->mapper()->map(Foo::class, Source::array([
    'items' => 'some value',
]));
```

Currently my workaround is to not map it to array of objects but to union of string and array shape and do the mapping later separately which works but it is not as comfortable as it could be.
