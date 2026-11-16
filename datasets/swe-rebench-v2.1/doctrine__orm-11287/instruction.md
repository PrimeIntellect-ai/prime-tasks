Doctrine\ORM\QueryBuilder::setParameter and ArrayParameterType in DBAL 4.0.0
<!--
Before reporting a BC break, please consult the upgrading document to make sure it's not an expected change: https://github.com/doctrine/orm/blob/2.9.x/UPGRADE.md
-->

### BC Break Report

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q        |   A
|------------ | ------
| BC Break    | yes
| Version     | 3.0.0

#### Summary

<!-- Provide a summary describing the problem you are experiencing. -->

`Doctrine\ORM\QueryBuilder::setParameter()` needs an optional parameter for complex data types sometimes and in 3.x version, it expects `string|int|null` and can be linked via `Doctrine\DBAL\Connection` e.g. `Doctrine\DBAL\Connection::PARAM_STR_ARRAY`. These values used to be as int datatype and have been deprecated. Now these constants are linked to `Doctrine\DBAL\ArrayParameterType` class. In 4.0.0 class ArrayParameterType has been converted to Enums but setParameter() is still accepting old `string|int|null` resulting following error

More info at https://github.com/doctrine/dbal/issues/6309
