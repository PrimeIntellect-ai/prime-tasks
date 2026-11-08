NoSuperfluousPhpdocTagsFixer - doesn't work with type alteration
```php
<?php
class Foo {
    /**
     * @var int|string $bar
     */
    private int|string $bar;
}
```

```php
    /**
     * @dataProvider provideFixPhp80Cases
     * @requires PHP 8.0
     */
    public function testFixPhp80(string $expected, ?string $input = null, array $config = []): void
    {
        $this->fixer->configure($config);
        $this->doTest($expected, $input);
    }

    public function provideFixPhp80Cases(): \Generator
    {
        yield [
                '<?php
class Foo {
    /**
     */
    private int|string $bar;
}',
                '<?php
class Foo {
    /**
     * @var int|string $bar
     */
    private int|string $bar;
}',
        ];

        yield 'static return' => [
            '<?php
class Foo {
    /**
     */
    public function foo($foo): static {}
}',
            '<?php
class Foo {
    /**
     * @return static
     */
    public function foo($foo): static {}
}',
        ];
    }
```

### Additional contract requirements

- Remove redundant `@var`, `@param`, and `@return` type tags when their types match the corresponding native property, parameter, or return type, including native union types.
- Treat unions as equivalent when they contain the same alternatives regardless of order. Count `null` as an alternative when it appears in the native union. Do not remove a tag when its type adds detail or its alternatives differ from the native type.
