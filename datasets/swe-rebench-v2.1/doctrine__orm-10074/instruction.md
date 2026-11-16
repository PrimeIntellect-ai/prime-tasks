Fetched Entity with native Enum field with non empty changeSet (Enum <=> string)
### Bug Report

```php
// Order.php
    #[Column(type: Types::STRING, nullable: false, enumType: OrderStatus::class, options: ['charset' => 'utf8', 'collation' => 'utf8_unicode_ci'])]
    private OrderStatus $orderStatus;


// code.
$order = new Order();
$em->flush();
$em->clear();

$freshOrder = $em->createQueryBuilder()->select('o')->from(Order::class, 'o')->setMaxResults(1)->getQuery()->getSingleResult();

$uow->computeChangeSets();
$em->getUnitOfWork()->isScheduledForDelete($order); // returns true.
```

(The freshEneity is scheduled for the update because in the changeSet is 'strinngValue' of Enum::Foo.

But when I get the Entity like this

```php
$freshEntity = $this->getEntityManager()->find(Order::class, $orderId);
$uow->computeChangeSets();
$em->getUnitOfWork()->isScheduledForUpdate($order); // returns false, there is no update on fresh Entity.
```

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q        |   A
|------------ | ------
| BC Break    | yes
| Version     | 2.13.x-dev

#### Summary

The $freshEntity with native Enum field shouldn't scheduled for updated
<!-- Provide a summary describing the problem you are experiencing. -->


the failing test case is here https://github.com/doctrine/orm/pull/10073
