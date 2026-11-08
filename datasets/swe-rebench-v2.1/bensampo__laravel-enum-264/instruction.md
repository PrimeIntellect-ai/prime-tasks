getDescription() throws error if value does not exist in v5
In v4, calling `getDescription()` with an incorrect value returns an empty string, but in v5 it throws an Error.

```
class MyEnum extends Enum {
   const MyValue = 'MyValue';
}
var_dump(MyEnum::getDescription('no'));
```

```
PHP Fatal error:  Uncaught Error: Call to a member function getAttributes() on bool in /project/vendor/bensampo/laravel-enum/src/Enum.php:406
Stack trace:
#0 /project/vendor/bensampo/laravel-enum/src/Enum.php(369): BenSampo\Enum\Enum::getAttributeDescription('no')
#1 /project/foo.php(12): BenSampo\Enum\Enum::getDescription('no')
#2 {main}
  thrown in /project/vendor/bensampo/laravel-enum/src/Enum.php on line 406
```
