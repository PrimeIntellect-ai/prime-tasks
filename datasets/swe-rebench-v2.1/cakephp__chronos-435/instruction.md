2.4.x: b/c break in Cake\Chronos\Date::create()
Updating Chronos to version 2.4.x introduces following b/c break:

Calling `Cake\Chronos\Date::create()` without any arguments results in an `ArgumentCountError`.

`ArgumentCountError: Too few arguments to function Cake\Chronos\ChronosDate::create(), 0 passed in [...] and exactly 3 expected in /var/www/html/vendor/cakephp/chronos/src/ChronosDate.php:154`

Before version 2.4.0 `Date::create()` was inherited from the `FactoryTrait` with all arguments optional. Now the trait's function is overridden by `ChronosDate`'s own implementation where parameters differ.
