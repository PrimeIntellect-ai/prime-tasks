2.13.2 breaks all queries with object hydration for entities using Enum fields
<!--
Before reporting a BC break, please consult the upgrading document to make sure it's not an expected change: https://github.com/doctrine/orm/blob/2.9.x/UPGRADE.md
-->

### BC Break Report

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q        |   A
|------------ | ------
| BC Break    | yes
| Version     | 2.13.2

#### Summary

[This change](https://github.com/doctrine/orm/pull/10041/files#diff-f1936bc3177c94ebd06906a54a439e496b410cfee881d6740ac344f03382e0ddR468) in #10041 breaks all queries with object hydration for entities with an Enum field.

#### Previous behavior

It worked.

#### Current behavior

Exception with stack trace:

```
TypeError:
App\Domain\Channel\ChannelId::from(): Argument #1 ($value) must be of type string, App\Domain\Channel\ChannelId given

  at vendor/doctrine/orm/lib/Doctrine/ORM/Mapping/ReflectionEnumProperty.php:93
  at App\Domain\Channel\ChannelId::from()
     (vendor/doctrine/orm/lib/Doctrine/ORM/Mapping/ReflectionEnumProperty.php:93)
  at Doctrine\ORM\Mapping\ReflectionEnumProperty->initializeEnumValue()
     (vendor/doctrine/orm/lib/Doctrine/ORM/Mapping/ReflectionEnumProperty.php:77)
  at Doctrine\ORM\Mapping\ReflectionEnumProperty->setValue()
     (vendor/doctrine/orm/lib/Doctrine/ORM/UnitOfWork.php:2745)
  at Doctrine\ORM\UnitOfWork->createEntity()
     (vendor/doctrine/orm/lib/Doctrine/ORM/Internal/Hydration/ObjectHydrator.php:266)
  at Doctrine\ORM\Internal\Hydration\ObjectHydrator->getEntity()
     (vendor/doctrine/orm/lib/Doctrine/ORM/Internal/Hydration/ObjectHydrator.php:492)
  at Doctrine\ORM\Internal\Hydration\ObjectHydrator->hydrateRowData()
     (vendor/doctrine/orm/lib/Doctrine/ORM/Internal/Hydration/ObjectHydrator.php:148)
  at Doctrine\ORM\Internal\Hydration\ObjectHydrator->hydrateAllData()
     (vendor/doctrine/orm/lib/Doctrine/ORM/Internal/Hydration/AbstractHydrator.php:270)
  at Doctrine\ORM\Internal\Hydration\AbstractHydrator->hydrateAll()
     (vendor/doctrine/orm/lib/Doctrine/ORM/AbstractQuery.php:1224)
  at Doctrine\ORM\AbstractQuery->executeIgnoreQueryCache()
     (vendor/doctrine/orm/lib/Doctrine/ORM/AbstractQuery.php:1165)
  at Doctrine\ORM\AbstractQuery->execute()
     (vendor/doctrine/orm/lib/Doctrine/ORM/AbstractQuery.php:953)
  at Doctrine\ORM\AbstractQuery->getOneOrNullResult()
     (src/Infrastructure/Doctrine/ORM/Repository/OrderRepository.php:51)
  at App\Infrastructure\Doctrine\ORM\Repository\OrderRepository->get()
     (src/Infrastructure/Symfony/Controller/Account/OrderDetailAction.php:43)
  at App\Infrastructure\Symfony\Controller\Account\OrderDetailAction->__invoke()
     (vendor/symfony/http-kernel/HttpKernel.php:153)
  at Symfony\Component\HttpKernel\HttpKernel->handleRaw()
     (vendor/symfony/http-kernel/HttpKernel.php:75)
  at Symfony\Component\HttpKernel\HttpKernel->handle()
     (vendor/symfony/http-kernel/Kernel.php:202)
  at Symfony\Component\HttpKernel\Kernel->handle()
     (vendor/symfony/runtime/Runner/Symfony/HttpKernelRunner.php:35)
  at Symfony\Component\Runtime\Runner\Symfony\HttpKernelRunner->run()
     (vendor/autoload_runtime.php:29)
  at require_once('/srv/share/vendor/autoload_runtime.php')
     (public/index.php:7)
```

#### How to reproduce

I have an `Order` entity with a `ChannelId` field that looks like this (simplified):

```
/** @final */
#[ORM\Entity]
#[ORM\Table(name: '`order`')]
class Order
{
    /** @psalm-immutable */
    #[ORM\Id]
    #[ORM\Column(type: 'order_id')]
    private OrderId $id

    /** @psalm-immutable */
    #[ORM\Column(type: 'string', enumType: ChannelId::class)]
    private ChannelId $channelId;
}
```

And a repository (simplified) with this method:

```
/** @throws OrderWithIdDoesNotExist */
public function get(OrderId $orderId): Order
{
    $manager = $this->registry->getManagerForClass(Order::class);
    $repository = $manager->getRepository(Order::class);

    $queryBuilder = $repository->createQueryBuilder('o');
    $queryBuilder->where('o.id = :id');
    $queryBuilder->setParameter('id', $orderId->toString());

    $order = $queryBuilder->getQuery()->getOneOrNullResult();

    if (! $order instanceof Order) {
        throw new OrderWithIdDoesNotExist($orderId);
    }

    return $order;
}
```

I'll see if I can come up with reproducing test case.
