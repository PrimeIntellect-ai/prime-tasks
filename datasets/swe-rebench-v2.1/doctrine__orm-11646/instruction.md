Not throwing proper exception when in transaction
### Bug Report

|    Q        |   A
|------------ | ------
| Version     | 2.6.3

#### Summary

EntityManager tries to rollback the transaction when exception is thrown during commit operation. The rollback is performed through DBAL Connection. The problem is that the transaction is no longer active and when DBAL Connection tries to rollback through `PDOConnection`, _There is no active transaction_ exception is thrown instead and the original exception is lost. So user has no easy way to know actual exception and gets _There is no active transaction_ instead.

#### Current behavior

1. `PDOException` _A_ `SQLSTATE[23505]: Unique violation: 7 ERROR:  duplicate key value violates unique constraint ...` occurs on commit in https://github.com/doctrine/doctrine2/blob/master/lib/Doctrine/ORM/EntityManager.php#L238
2. Transaction is attempting to rollback https://github.com/doctrine/doctrine2/blob/master/lib/Doctrine/ORM/EntityManager.php#L243 before exception _A_ is thrown on https://github.com/doctrine/doctrine2/blob/master/lib/Doctrine/ORM/EntityManager.php#L245
3. DBAL `Connection::rollback()` is called where `$this->_conn->rollBack();` is called. `_conn` is instance of `PDOConnection` that throws _There is no active transaction_ exception instead and the original exception is lost.

#### Expected behavior

The original exception is properly thrown.
