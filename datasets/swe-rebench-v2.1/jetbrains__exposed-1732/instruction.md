Update with join fails on H2 in MySql mode
When using H2 in MySql mode the dialect's function provider generates a "MERGE INTO..." clause which fails to execute.

The [corresponding code](https://github.com/JetBrains/Exposed/blob/da82e389a4080c19521cb836010c4bad7690f84c/exposed-core/src/main/kotlin/org/jetbrains/exposed/sql/vendors/H2.kt#L141-L168) explicitly ignores the MySql mode setting in line 165 and returns the original function provider (H2DataTypeProvider) which generates an invalid MySql query.

Reproduction using exposed 0.40.1:

``` kotlin
import org.jetbrains.exposed.dao.id.LongIdTable
import org.jetbrains.exposed.sql.Database
import org.jetbrains.exposed.sql.DatabaseConfig
import org.jetbrains.exposed.sql.SchemaUtils
import org.jetbrains.exposed.sql.transactions.transaction
import org.jetbrains.exposed.sql.update

object Parent : LongIdTable("parent") {
    val foo = varchar("foo", 255)
}

object Child : LongIdTable("child") {
    val bar = varchar("bar", 255)
    val parentId = reference("parent_id", Parent)
}


fun main(args: Array<String>) {
    val db = Database.connect(
        "jdbc:h2:mem:db;DB_CLOSE_DELAY=-1;MODE=MYSQL",
        user = "a",
        password = "a",
        databaseConfig = DatabaseConfig {
            useNestedTransactions = true
        }
    )

    transaction(db) { SchemaUtils.create(Parent, Child) }

    transaction {
        Parent.innerJoin(Child)
            .update({ Parent.foo eq "foo" }) {
                it[Child.bar] = "baz"
            }
    }
}
```

Output:

```
Exception in thread "main" org.jetbrains.exposed.exceptions.ExposedSQLException: org.h2.jdbc.JdbcSQLSyntaxErrorException: Syntax error in SQL statement "MERGE INTO CHILD USING PARENT ON PARENT.ID = CHILD.PARENT_ID WHEN MATCHED THEN UPDATE SET CHILD.BAR=? [*]WHERE PARENT.FOO = ?"; SQL statement:
MERGE INTO CHILD USING PARENT ON PARENT.ID = CHILD.PARENT_ID WHEN MATCHED THEN UPDATE SET CHILD.BAR=? WHERE PARENT.FOO = ? [42000-214]
SQL: [Failed on expanding args for UPDATE: org.jetbrains.exposed.sql.statements.UpdateStatement@1edb61b1]
	at org.jetbrains.exposed.sql.statements.Statement.executeIn$exposed_core(Statement.kt:49)
	at org.jetbrains.exposed.sql.Transaction.exec(Transaction.kt:140)
	at org.jetbrains.exposed.sql.Transaction.exec(Transaction.kt:126)
	at org.jetbrains.exposed.sql.statements.Statement.execute(Statement.kt:28)
	at org.jetbrains.exposed.sql.QueriesKt.update(Queries.kt:232)
	at org.jetbrains.exposed.sql.QueriesKt.update$default(Queries.kt:229)
	at hu.regens.kotlingradle.MainKt$main$2.invoke(Main.kt:34)
	at hu.regens.kotlingradle.MainKt$main$2.invoke(Main.kt:32)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.inTopLevelTransaction$run(ThreadLocalTransactionManager.kt:214)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.access$inTopLevelTransaction$run(ThreadLocalTransactionManager.kt:1)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt$inTopLevelTransaction$1.invoke(ThreadLocalTransactionManager.kt:240)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.keepAndRestoreTransactionRefAfterRun(ThreadLocalTransactionManager.kt:248)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.inTopLevelTransaction(ThreadLocalTransactionManager.kt:239)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt$transaction$1.invoke(ThreadLocalTransactionManager.kt:189)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.keepAndRestoreTransactionRefAfterRun(ThreadLocalTransactionManager.kt:248)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.transaction(ThreadLocalTransactionManager.kt:159)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.transaction(ThreadLocalTransactionManager.kt:146)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.transaction$default(ThreadLocalTransactionManager.kt:145)
	at hu.regens.kotlingradle.MainKt.main(Main.kt:32)
Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Syntax error in SQL statement "MERGE INTO CHILD USING PARENT ON PARENT.ID = CHILD.PARENT_ID WHEN MATCHED THEN UPDATE SET CHILD.BAR=? [*]WHERE PARENT.FOO = ?"; SQL statement:
MERGE INTO CHILD USING PARENT ON PARENT.ID = CHILD.PARENT_ID WHEN MATCHED THEN UPDATE SET CHILD.BAR=? WHERE PARENT.FOO = ? [42000-214]
	at org.h2.message.DbException.getJdbcSQLException(DbException.java:502)
	at org.h2.message.DbException.getJdbcSQLException(DbException.java:477)
	at org.h2.message.DbException.get(DbException.java:223)
	at org.h2.message.DbException.get(DbException.java:199)
	at org.h2.message.DbException.getSyntaxError(DbException.java:247)
	at org.h2.command.Parser.getSyntaxError(Parser.java:898)
	at org.h2.command.Parser.prepareCommand(Parser.java:572)
	at org.h2.engine.SessionLocal.prepareLocal(SessionLocal.java:631)
	at org.h2.engine.SessionLocal.prepareCommand(SessionLocal.java:554)
	at org.h2.jdbc.JdbcConnection.prepareCommand(JdbcConnection.java:1116)
	at org.h2.jdbc.JdbcPreparedStatement.<init>(JdbcPreparedStatement.java:92)
	at org.h2.jdbc.JdbcConnection.prepareStatement(JdbcConnection.java:1044)
	at org.jetbrains.exposed.sql.statements.jdbc.JdbcConnectionImpl.prepareStatement(JdbcConnectionImpl.kt:77)
	at org.jetbrains.exposed.sql.statements.Statement.prepared(Statement.kt:24)
	at org.jetbrains.exposed.sql.statements.Statement.executeIn$exposed_core(Statement.kt:47)
	... 18 more
```
