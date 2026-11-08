Cannot create table with array type
I would like to create a table with an array type but I have an error:
```sql
genji> CREATE TABLE foo (name text primary key, animals array);
found array, expected ) at line 1, char 50
genji>
```

Is it by design or not?
