Serialization to json - Namespaces are not escaped
Hello ;)

I have a problem with serializing object namespaces (FQCN). Code below shows this situation:

Serilized objects:
```php
final class CheckProduct
{
    public function __construct(
        public string $name,
        public string $class,
    ) {
    }
}

final class Strawberry
{
}
```

Test:
```php
    #[Test]
    public function can_serialize_object_with_class_namespace(): void
    {
        // given
        $normalizer = (new \CuyZ\Valinor\MapperBuilder())
            ->normalizer(\CuyZ\Valinor\Normalizer\Format::json());
        // and
        $object = new CheckProduct('strawberry', Strawberry::class);

        // when
        $json = $normalizer->normalize($object);

        // then
        self::assertEquals(json_encode($object), $json);
    }
```

// output of $json variable
```
{"name":"strawberry","class":"Test\Unit\Strawberry"}
```
It's not a valid json, because backslashes are not escaped. It should be like this:
```
{"name":"strawberry","class":"Test\\Unit\\Strawberry"}
```

Is it a bug or did I forgot something?

### Additional contract requirements

- The JSON formatter must also escape forward slashes: the value `Europe/Paris` serializes as `"Europe\/Paris"`, and an object with `name` set to `Europe/Paris` and `country_code` set to `FR` serializes as `{"name":"Europe\/Paris","country_code":"FR"}`.
