Regression from SqlDelight 1.3.0 to 1.4.0 - Erroneous 'Multiple columns found' error
Dialect: SQLite

failing sql:

```sql
CREATE TABLE foo(
    id TEXT NOT NULL PRIMARY KEY
);

CREATE TABLE bar(
    id TEXT NOT NULL PRIMARY KEY
);

CREATE TABLE baz(
    id TEXT NOT NULL PRIMARY KEY
);

repro:
SELECT id FROM foo
WHERE id IN (
    SELECT foo.id FROM foo
    LEFT JOIN bar ON foo.id = bar.id
    LEFT JOIN baz ON foo.id = baz.id
);
```

This is a reduced repro of a more complex query that I have in my Android app, however the query above labeled `repro` works fine with SqlDelight 1.3.0 but when I upgrade to 1.4.0, it fails with the error message:
```
<path to sq files>/Foo.sq line 17:25 - Multiple columns found with name id
14    SELECT id FROM foo
15    WHERE id IN (
16        SELECT foo.id FROM foo
17        LEFT JOIN bar ON foo.id = bar.id
                               ^^
18        LEFT JOIN baz ON foo.id = baz.id
19    )

<path to sq files>/Foo.sq line 18:25 - Multiple columns found with name id
14    SELECT id FROM foo
15    WHERE id IN (
16        SELECT foo.id FROM foo
17        LEFT JOIN bar ON foo.id = bar.id
18        LEFT JOIN baz ON foo.id = baz.id
                               ^^
19    )

```
