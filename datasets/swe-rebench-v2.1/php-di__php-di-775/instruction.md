PSR-11 exception interfaces
Hello,

I've encountered an issue where exceptions thrown by container do not implement PSR-11 interfaces. Below is a code to better illustrate the issue. In short, my code relies on `Psr\Container\ContainerInterface` and it does not care which particular implementation comes in, so I strictly follow the PSR-11 and only look at `ContainerInterface` docs and ignore the specifics of how PHP-DI implements it. However, when PHP-DI throws an exception the exception does not implement the interface of PSR-11, this leads to a situation where I'm forced to either a) catch more generic `\Exception`, but this could catch some exceptions that are not related to container; b) catch `DI\Definition\Exception\InvalidDefinition`, but that would tie my code to PHP-DI which defeats the purpose of PSR-11.

I'm happy to contribute with code fixes, but before I do that, I'd like to better understand this situation and agree on whether this is considered a bug and what would be the best approach to fix it.

```php
<?php

declare(strict_types=1);

require_once __DIR__ . '/vendor/autoload.php';

class Foo
{
    public function __construct(array $foo)
    {
        // Do something with $foo here.
    }
}

$builder = new \DI\ContainerBuilder();
$container = $builder->build();

try {
    $container->get(Foo::class);
} catch (\Psr\Container\NotFoundExceptionInterface $e) {
    die('a');
    // Not getting in here as the Foo is concrete class and can be resolved, even tho it's not registered in container.
    // Is this the the expected behaviour?
} catch (\Psr\Container\ContainerExceptionInterface $e) {
    die('b');
    // Not getting in here either as the exception that actually is throw (`DI\Definition\Exception\InvalidDefinition`)
    // does not implement `\Psr\Container\ContainerExceptionInterface` interface.
    // Is this by expected? Isn't this violation of [PSR-11 rule 1.2](https://www.php-fig.org/psr/psr-11/#12-exceptions)?
} catch (\Exception $e) {
    var_dump(get_class($e));
    var_dump($e instanceof \Psr\Container\ContainerExceptionInterface);
    die('c');
}
```

Output:
```
$ php test.php
string(41) "DI\Definition\Exception\InvalidDefinition"
bool(false)
c
```
