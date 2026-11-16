Parsing enum array not working
Hey there, I am trying to parse a array of integers to a array of integer backed enums like so:

```php
enum SomeEnum: int
{
    case SOME_VALUE  = 1;
    case OTHER_VALUE = 2;
}

class ExampleObject
{
    public function __construct(
        /** @var \SomeEnum[] */
        public array $enumArray,
    ) {}
}

(new \CuyZ\Valinor\MapperBuilder())
    ->mapper()
    ->map(
        ExampleObject::class,
        ['enumArray' => [1, 2]],
    );
```

In this test I get:

```
Fatal error: Uncaught TypeError: CuyZ\Valinor\Type\Parser\GenericCheckerParser::parse(): Argument #1 ($raw) must be of type string, null given, called in vendor/cuyz/valinor/src/Definition/Repository/Reflection/TypeResolver/ClassParentTypeResolver.php on line 47 and defined in vendor/cuyz/valinor/src/Type/Parser/GenericCheckerParser.php:30
```

However in my application it fails differently:

```
Attempt to read property "name" on false {"exception":"[object] (ErrorException(code: 0): Attempt to read property \"name\" on false at vendor/cuyz/valinor/src/Definition/Repository/Reflection/TypeResolver/ClassParentTypeResolver.php:39)
```

I was unable to get a minimal case for this error mode in a minimal way but showing it here in case it's helpful.

[HIDDEN]

Maybe I am doing something wrong or incorrect here, but from my perspective something is not right 😅 I have been trying to dig around but it's a pretty complex codebase so I was unable to devise some fix or better understanding at this time.

### Additional contract requirements

Enum types written with a fully qualified name, including a leading namespace separator, must resolve to that enum when mapping object properties and array elements.
