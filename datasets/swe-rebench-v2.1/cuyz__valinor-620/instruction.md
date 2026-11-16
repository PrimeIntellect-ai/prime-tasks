CannotResolveObjectType: Impossible to resolve an implementation
Hi, since 040b9093f16a7446f6e678ae992754c8170bcad9 the following no longer works:

```php
// test.php

<?php

require_once __DIR__ . '/vendor/autoload.php';

interface Foo {}
final readonly class Baz implements Foo {}
final readonly class Bar implements Foo {}

final readonly class Dto
{
    public function __construct(
        public Foo|string|null $foo = null,
    ) {}
}

$mapper = (new \CuyZ\Valinor\MapperBuilder())->mapper();
$foo = $mapper->map(Dto::class, ['foo' => 'baz']);

var_dump($foo);
```

I get the following result when calling `php test.php`:

```
Fatal error: Uncaught CuyZ\Valinor\Mapper\Tree\Exception\CannotResolveObjectType: Impossible to resolve an implementation for `Foo`. in /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/InterfaceNodeBuilder.php:59
Stack trace:
#0 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/IterableNodeBuilder.php(26): CuyZ\Valinor\Mapper\Tree\Builder\InterfaceNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#1 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/RootNodeBuilder.php(25): CuyZ\Valinor\Mapper\Tree\Builder\IterableNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#2 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/UnionNodeBuilder.php(43): CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell))
#3 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/TypeNodeBuilder.php(73): CuyZ\Valinor\Mapper\Tree\Builder\UnionNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#4 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/InterfaceNodeBuilder.php(40): CuyZ\Valinor\Mapper\Tree\Builder\TypeNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#5 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/IterableNodeBuilder.php(26): CuyZ\Valinor\Mapper\Tree\Builder\InterfaceNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#6 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/RootNodeBuilder.php(25): CuyZ\Valinor\Mapper\Tree\Builder\IterableNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#7 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/ObjectNodeBuilder.php(107): CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell))
#8 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/ObjectNodeBuilder.php(62): CuyZ\Valinor\Mapper\Tree\Builder\ObjectNodeBuilder->children(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Object\ArgumentsValues), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#9 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/TypeNodeBuilder.php(73): CuyZ\Valinor\Mapper\Tree\Builder\ObjectNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#10 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/InterfaceNodeBuilder.php(62): CuyZ\Valinor\Mapper\Tree\Builder\TypeNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#11 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/IterableNodeBuilder.php(26): CuyZ\Valinor\Mapper\Tree\Builder\InterfaceNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#12 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/RootNodeBuilder.php(25): CuyZ\Valinor\Mapper\Tree\Builder\IterableNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell), Object(CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder))
#13 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/TypeTreeMapper.php(48): CuyZ\Valinor\Mapper\Tree\Builder\RootNodeBuilder->build(Object(CuyZ\Valinor\Mapper\Tree\Shell))
#14 /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/TypeTreeMapper.php(28): CuyZ\Valinor\Mapper\TypeTreeMapper->node('Dto', Array)
#15 /Users/elias/test/valinor-error/test.php(17): CuyZ\Valinor\Mapper\TypeTreeMapper->map('Dto', Array)
#16 {main}
  thrown in /Users/elias/test/valinor-error/vendor/cuyz/valinor/src/Mapper/Tree/Builder/InterfaceNodeBuilder.php on line 59
```

This is the result when using the previous commit (f8eedc944978ecfaaa0487ac3a9068be1e7f8747):

```
object(Dto)#135 (1) {
  ["foo"]=>
  string(3) "baz"
}
```
