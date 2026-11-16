setFetchMode() is ignored - Exception eager Fetch Join With Not Allowed
```
Entity/Category.php

#[ORM\Entity]
class Category
{
    #[ORM\Id]
    #[ORM\Column(type: 'integer')]
    #[ORM\GeneratedValue(strategy: 'AUTO')]
    private int $id;

    #[ORM\ManyToOne(targetEntity: 'Category', fetch: 'EAGER')]
    #[ORM\JoinColumn(name: 'root_id', referencedColumnName: 'id', onDelete: 'CASCADE')]
    private ?Category $root = null;
}
```

Query
```
$qb = $this->createQueryBuilder('content')
            ->join('content.category', 'category')
            ->join('category.root', 'categoryRoot', Expr\Join::WITH, 'categoryRoot = :root')
            ->setParameter('root', $host->getCategory());

$query = $qb->getQuery();
$query->setFetchMode(Category::class, 'categoryRoot', ClassMetadata::FETCH_LAZY);
```

Result
```
Doctrine\ORM\Query\QueryException

Associations with fetch-mode=EAGER may not be using WITH conditions in
             "[App\Entity\Category]"
```

[HIDDEN]
[HIDDEN]

https://github.com/doctrine/orm/blame/28d03e41f7b58781c516404bf179806e10a84ec5/lib/Doctrine/ORM/Query/SqlWalker.php#L897

Maybe related with
https://github.com/doctrine/orm/issues/7860

### Additional contract requirements

- When a query overrides an EAGER association to FETCH_LAZY, a WITH condition on that join must not trigger the eager-fetch exception, and SQL generation must be allowed to proceed.
