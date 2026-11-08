Fetch mode hint is ignored when using `Paginator`
### Bug Report

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q                                        |   A
|-------------------------------------------- | --------------
| Version                                     | 2.20.0 / 3.3.0
| Previous working version                    | 2.19.8 / 3.2.3

#### Summary

This is related to issue #11128 and PR #11445.

When a `fetch=EAGER` association is filtered using `WITH`, it raises an error unless fetch mode is overridden by calling `setFetchMode(LAZY)` over the association.

This worked well after the fix in #11445.

Somehow, in 2.20.x and 3.3.x this bug returned, partially, only when using `Paginator` with `fetchJoinCollection` parameter set to `true`.

Seems like #11188 introduced this bug.


#### Current behavior

An exception is raised even when fetch mode is overridden.

#### Expected behavior

It should work the same with or without pagination.

#### How to reproduce

See test in https://github.com/aprat84/orm/tree/gh-11741

```
vendor/bin/phpunit --filter testSubselectFetchJoinWithAllowedWhenOverriddenNotEagerPaginator

There was 1 error:

1) Doctrine\Tests\ORM\Functional\EagerFetchCollectionTest::testSubselectFetchJoinWithAllowedWhenOverriddenNotEagerPaginator
Doctrine\ORM\Query\QueryException: Associations with fetch-mode=EAGER may not be using WITH conditions in "Doctrine\Tests\ORM\Functional\EagerFetchChild#owner".
```
