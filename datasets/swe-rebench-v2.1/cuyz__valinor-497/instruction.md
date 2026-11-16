Multidimensional arrays don't work
```
final class SomeClass
{
    // If I don't comment then it works fine
    //public readonly string $description;

    /** @var Identifier[] */
    public array $identifier;

}

final class Identifier
{
    public string $value;
}

$mapper = (new \CuyZ\Valinor\MapperBuilder())->allowSuperfluousKeys()->mapper();
$result = $mapper->map(SomeClass::class, [
    'identifier' => [
        ['value' => 'some-identifier'],
        ['value' => 'some-identifier2']
    ],
    'description' => 'Lorem ipsum…',
]);
```

```
Fatal error: Uncaught CuyZ\Valinor\Mapper\TypeTreeMapperError: Could not map type `SomeClass`. An error occurred at path identifier.identifier: Value array{0: array{…}, 1: array{…}} is not a valid string
```
