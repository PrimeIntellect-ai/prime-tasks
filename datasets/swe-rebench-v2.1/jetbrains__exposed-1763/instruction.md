Partial Indexes?
Exposed currently has no way to define partial indexes.

E.g:
```
CREATE UNIQUE INDEX my_index
    ON table (column_a, column_b)
 WHERE column_a IS NOT NULL
```

Use case:
Let's say I have a database of PEOPLE. Each member of PEOPLE has a "name" (text), as well as an optional reference to PEOPLE (i.e. "parent"). But I want to make sure that for each member of PEOPLE, if it has "children", each child must have a unique name. One way to implement this is to have (proposed syntax):

```
uniqueIndex(name, parent_id)
partialUniqueIndex(name).where { parent_id.isNull() }
```

Partial Indexes are supported by Postgresql and Sqlite, but I don't think Mysql has it.
