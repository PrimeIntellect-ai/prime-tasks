[DAO] Unable to implement entity class with ID column of reference type
## Summary
I can not implement DAO entity with ID, which is actually a reference to another table.

## Details
I have one global entity, which contains ID (of UUID type), type (simply text marker) and some other attributes of any entity, stored in other tables in database.
I also have other entities (for this example only one - see code below), which need to contain ID, that is actually saved in global table, so I made ID as a reference (+ added some useful overloads to CREATE and DELETE methods to keep database consistent and entity classes easy to use).

Everything is fine for CREATE/SELECT/DELETE methods (new global entities got created before task entities, their IDs got used for task entities, data got persisted into/loaded from DB, everything is in sync), but exception `java.lang.IllegalStateException: Table from Entity ID *common* differs from entity class *specific*` got thrown whenever I try to UPDATE entity in database (where `*common*` and `*specific*` are names of entity tables in database).
I know, where this exception is generating, and understand, that this was implemented to overcome using fields from wrong Table objects in queries, but this behaviour is incorrect in case, that I've described (i.e. when ID is not a simple column, but actually a reference to another table, in which case its' `columnType` property contains reference to other table).

Environment has following components:

<details>
<summary>Environment</summary>

Kotlin: 1.3.72 (JVM target 1.8)
Exposed: 0.23.1
SQLite (DB driver): 3.30.1

</details>

Here is code to reproduce this issue:

<details>
<summary>Code</summary>

```kotlin
import org.jetbrains.exposed.dao.*
import org.jetbrains.exposed.dao.id.*
import org.jetbrains.exposed.dao.id.EntityID
import org.jetbrains.exposed.dao.id.UUIDTable
import org.jetbrains.exposed.sql.*
import org.jetbrains.exposed.sql.transactions.*
import java.util.*

class GlobalEntity(id: EntityID<UUID>) : UUIDEntity(id) {
    companion object Repository : UUIDEntityClass<GlobalEntity>(DBTable)

    object DBTable : UUIDTable("global_entities") {
        val type = varchar("type", length = 255)
    }

    var type by DBTable.type
}

class TaskEntity(id: EntityID<UUID>) : UUIDEntity(id) {
    companion object Repository : UUIDEntityClass<TaskEntity>(DBTable) {
        override fun new(id: UUID?, init: TaskEntity.() -> Unit) = super.new(
            if (id !is UUID || GlobalEntity.findById(id) == null) {
                GlobalEntity.new(id) { type = "task" }.id.value
            } else {
                id
            },
            init
        )
    }

    object DBTable : IdTable<UUID>("tasks") {
        override val id = reference(
            "id",
            GlobalEntity.DBTable,
            onUpdate = ReferenceOption.CASCADE,
            onDelete = ReferenceOption.CASCADE
        )

        val name = varchar("name", length = 255)
        val description = text("description").nullable()

        override val primaryKey = PrimaryKey(id)
    }

    val global by GlobalEntity referencedOn DBTable.id
    var name by DBTable.name
    var description by DBTable.description

    override fun delete() {
        GlobalEntity.findById(id.value)?.delete()
        super.delete()
    }
}

fun main() {
    val db = Database.connect(/* configuration here */)
    // Migrate
    transaction(db) {
        addLogger(StdOutSqlLogger)

        SchemaUtils.create(
            GlobalEntity.DBTable,
            TaskEntity.DBTable
        )
    }

    // Create
    val id = transaction(db) {
        addLogger(StdOutSqlLogger)

        TaskEntity.new {
            name = "Hello"
            description = "World"
        }.id.value
    }

    // Read
    val entity1 = transaction(db) {
        addLogger(StdOutSqlLogger)

        TaskEntity.findById(id)!!
    }
    println("${entity1.id.value} | ${entity1.name} (${entity1.description})")

    // Update (this part fails)
    transaction(db) {
        addLogger(StdOutSqlLogger)

        entity1.name = "World"
        entity1.description = "Hello"
    }

    // Read (again)
    val entity2 = transaction(db) {
        addLogger(StdOutSqlLogger)

        TaskEntity.findById(id)!!
    }
    println("${entity2.id.value} | ${entity2.name} (${entity2.description})")

    // Delete
    transaction(db) {
        addLogger(StdOutSqlLogger)

        entity2.delete()
    }
    println("Done!")
}
```

</details>

And here is full log after executing this example:

<details>
<summary>Logs</summary>

```
SQL: CREATE TABLE IF NOT EXISTS global_entities (id BINARY(16) PRIMARY KEY, "type" VARCHAR(255) NOT NULL)
SQL: CREATE TABLE IF NOT EXISTS tasks (id BINARY(16) PRIMARY KEY, "name" VARCHAR(255) NOT NULL, description TEXT NULL, CONSTRAINT fk_tasks_id_id FOREIGN KEY (id) REFERENCES global_entities(id) ON DELETE CASCADE ON UPDATE CASCADE)
SQL: INSERT INTO global_entities (id, "type") VALUES ('90f78fd9-43f5-4d12-b501-cc7c604d5792', 'task')
SQL: INSERT INTO tasks (description, id, "name") VALUES ('World', '90f78fd9-43f5-4d12-b501-cc7c604d5792', 'Hello')
SQL: SELECT tasks.id, tasks."name", tasks.description FROM tasks WHERE tasks.id = '90f78fd9-43f5-4d12-b501-cc7c604d5792'
90f78fd9-43f5-4d12-b501-cc7c604d5792 | Hello (World)
SQL: SELECT tasks.id, tasks."name", tasks.description FROM tasks WHERE tasks.id = '90f78fd9-43f5-4d12-b501-cc7c604d5792'
Exception in thread "main" java.lang.IllegalStateException: Table from Entity ID global_entities differs from entity class tasks
	at org.jetbrains.exposed.dao.EntityBatchUpdate.addBatch(EntityBatchUpdate.kt:14)
	at org.jetbrains.exposed.dao.Entity.flush(Entity.kt:159)
	at org.jetbrains.exposed.dao.EntityCache.updateEntities(EntityCache.kt:58)
	at org.jetbrains.exposed.dao.EntityCache.flush(EntityCache.kt:84)
	at org.jetbrains.exposed.dao.EntityCache.flush(EntityCache.kt:49)
	at org.jetbrains.exposed.dao.EntityCacheKt.flushCache(EntityCache.kt:154)
	at org.jetbrains.exposed.dao.EntityLifecycleInterceptor.beforeCommit(EntityLifecycleInterceptor.kt:40)
	at org.jetbrains.exposed.sql.Transaction.commit(Transaction.kt:60)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt$inTopLevelTransaction$1.invoke(ThreadLocalTransactionManager.kt:157)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt$inTopLevelTransaction$2.invoke(ThreadLocalTransactionManager.kt:197)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.keepAndRestoreTransactionRefAfterRun(ThreadLocalTransactionManager.kt:205)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.inTopLevelTransaction(ThreadLocalTransactionManager.kt:196)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt$transaction$1.invoke(ThreadLocalTransactionManager.kt:134)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.keepAndRestoreTransactionRefAfterRun(ThreadLocalTransactionManager.kt:205)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.transaction(ThreadLocalTransactionManager.kt:106)
	at org.jetbrains.exposed.sql.transactions.ThreadLocalTransactionManagerKt.transaction(ThreadLocalTransactionManager.kt:104)
	at TestKt.main(Test.kt:90)
	at TestKt.main(Test.kt)
```

</details>

I need this to keep track of all IDs in the database, guarantee their uniqueness and for some other reasons, that are too specific to task, that I'm trying to implement.
Can you tell, if there is something wrong with sample code (and so it can be done in other way) or if this is actually a bug in Exposed?

### Additional contract requirements

- Updating an entity whose ID column is a reference to another table must succeed: after the update is committed, the changed values must be persisted and readable back from the database.
- The public class `org.jetbrains.exposed.dao.EntityBatchUpdate` exposes a public method `addBatch(entity: Entity<*>)` that accepts an entity. It must throw an `IllegalStateException` when the entity's class differs from the `EntityClass` the `EntityBatchUpdate` was created for.
