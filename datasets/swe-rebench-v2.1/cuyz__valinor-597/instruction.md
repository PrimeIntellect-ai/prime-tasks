Unsealed array with trailing comma causes parse error
Valinor currently fails to parse an unsealed array with a trailing comma:
```php
class Foo
{
    /**
     * @param array{
     *     a: int,
     *     b: int,
     *     ...,
     * } $arr
     */
    public function __construct(private readonly array $arr) {}
}

$foo = (new \CuyZ\Valinor\MapperBuilder())
    ->allowPermissiveTypes()
    ->mapper()
    ->map(Foo::class, ["arr" => ["a" => 1, "b" => 2]])
;
```
It's debatable whether this trailing comma is really appropriate, since `...` must appear last the comma isn't useful for diffs, but since Psalm and PHPStan both support it I think it would be good for it not to cause a parsing error.
