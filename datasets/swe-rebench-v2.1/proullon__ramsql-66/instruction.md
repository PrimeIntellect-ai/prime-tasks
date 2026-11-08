Sometimes ORM wrap columns with quotes
Hi @proullon ,

Some ORM wrap columns with quotes as in the example of GORM:
```sql
UPDATE "challenges" SET "deleted_at"='2022-07-11 14:52:45.804' WHERE "challenges"."deleted_at" IS NULL
```

But I get this error:
```
Syntax error near . \" deleted_at
```

Note that when testing the followings it works perfectly:

```sql
UPDATE "challenges" SET "deleted_at"='2022-07-11 14:52:45.804' WHERE "challenges".deleted_at IS NULL
```

```sql
UPDATE "challenges" SET "deleted_at"='2022-07-11 14:52:45.804' WHERE challenges.deleted_at IS NULL
```

Is it possible you accept quotes for columns as you do for tables?

Thank you,
