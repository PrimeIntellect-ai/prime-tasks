Wrong type inference for QueryBuilder::update and QueryBuilder::delete.
The following code
```
$result = $this->getEntityManager()
            ->getRepository(ProductCrossSell::class)
            ->createQueryBuilder('pcs')
            ->where('pcs.id IN (:ids)')
            ->setParameter('ids', $ids)
            ->delete()
            ->getQuery()
            ->getResult();

\PHPStan\dumpType($result);
```
Is considering `$result` as an array. But it's an int: the number of deleted elements. Same with `update()`

It was introduce by https://github.com/phpstan/phpstan-doctrine/pull/232 cc @arnaud-lb

### Additional contract requirements

A result should be inferred as an affected-row integer only when the query is known to be a DELETE or UPDATE. When the query result may or may not represent a DML operation, do not assume an affected-row integer or a result array; preserve the method's declared return type. Queries known to be non-DML should retain their normal result-type inference.
