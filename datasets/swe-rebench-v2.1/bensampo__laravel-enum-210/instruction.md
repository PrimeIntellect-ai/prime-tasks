Incorrect description out when uppercase key with numeric suffix
I've noticed an issue when my keys are in the following format, the generated description has a space between every character


```php
class MyEnum extends Enum {
    public const SOME_INTERESTING_KEY_1 = 10;
    public const SOME_INTERESTING_KEY_2 = 20;
}
```

```php
echo MyEnum::getDescription(20);
```

The output is `S o m e  i n t e r e s t i n g  k e y 2`
