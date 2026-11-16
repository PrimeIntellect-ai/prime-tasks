No ForeignKeyConstraintViolationException exception when trying to remove an entity
### Bug Report

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q        |   A
|------------ | ------
| BC Break    | kinda
| Version     | 2.15.2

#### Summary

Since the following change
<img width="1449" alt="CleanShot 2023-06-03 at 08 04 00@2x" src="https://github.com/doctrine/orm/assets/80641364/7e024efb-8a54-46de-9990-df19fa1de179">
Doctrine stopped throwing `ForeignKeyConstraintViolationException` and (from what I noticed) it removes the entity from the database. What's more interesting, if we add the deleted lines, and leave the same code at the end of the method – it doesn't work. So putting this `if` statement somehow breaks the expected behavior.

#### Current behavior

No `ForeignKeyConstraintViolationException` 🤷🏼‍♂️.
#### How to reproduce

#10753

#### Expected behavior

`ForeignKeyConstraintViolationException` should be thrown.
