How can I create tables in different schemas in exposed?
Me need to use the 'exposed' library itself to create tables in different schemas simply, transparently, and without SQL.

A simple table in the library is declared like this:

```
    object TestTable : IntIdTable("TEST_TABLE", "ID") {
        val name = text("name").default("any string")
        val number = integer("number").uniqueIndex("number_unique")
    }

```
And it is created in the database, then, so:

```
SchemaUtils.create(TestTable)
```

But, if you declare the table like this:

```
    object TestTable : IntIdTable("TEST.TEST_TABLE", "ID") {
        val name = text("name").default("any string")
        val number = integer("number").uniqueIndex("number_unique")
    }

```
Then it will not be able to work out the following:
```
SchemaUtils.createMissingTablesAndColumns(TestTable)
```

Because the fact of the presence/absence of columns is checked by the function "`SchemaUtils.createMissingTablesAndColumns`" exclusively in the default schema, regardless of which schema the table is created in.


I know that there is a `Schema` class designed to describe schemas. But the `Table` class doesn't have the `schema` property. I also couldn't find any annotations like `OnSchema` in the 'exposed` library.

Please tell me how I can tell the "exposed" library that I want to use a specific table in a specific schema.
