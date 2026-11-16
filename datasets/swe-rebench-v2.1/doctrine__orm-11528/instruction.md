QueryBuilder function "createNamedParameter" like in doctrine/dbal
### Feature Request

Hello,
i noticed that the function "createNamedParameter" does not exist in the [QueryBuilder](https://github.com/doctrine/orm/blob/2.12.x/lib/Doctrine/ORM/QueryBuilder.php), unlike the [QueryBuilder](https://github.com/doctrine/dbal/blob/3.3.x/src/Query/QueryBuilder.php#L1463) from "doctrine/dbal".
Is there a reason why it is not available in "doctrine/orm"?
Otherwise I can create a pull request.

|    Q        |   A
|------------ | ------
| New Feature | yes
| RFC         | no
| BC Break    | no

#### Summary

Documentation of the function "createNamedParameter": https://www.doctrine-project.org/projects/doctrine-dbal/en/latest/reference/query-builder.html#binding-parameters-to-placeholders
