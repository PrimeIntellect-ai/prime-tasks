Invalid Sqlite schema.sql when INTEGER PRIMARY KEY AUTOINCREMENT is used
## TL;DR

Dbmate always outputs the full schema, including `sqlite_sequence` which is auto-generated when autoincrement appears in at least one table definition. This table is reserved for internal use in sqlite and cannot be created by the user (see https://www.sqlite.org/autoinc.html section 3).

This schema.sql file fails to load on an empty database.

## Setup:
dbmate 1.15.0, sqlite 3.39

## To reproduce:

Run `dbmate new test`, let's call it `db/migrations/20220818223405_test.sql`.

The file should contain:

```
-- migrate:up

create table t (
  id INTEGER PRIMARY KEY AUTOINCREMENT
);

-- migrate:down

drop table t
```

Run `dbmate -u sqlite3:test.db up`

The file `db/schema.sql` should contain:

```
CREATE TABLE IF NOT EXISTS "schema_migrations" (version varchar(255) primary key);
CREATE TABLE t (
  id INTEGER PRIMARY KEY AUTOINCREMENT
);
CREATE TABLE sqlite_sequence(name,seq);
-- Dbmate schema migrations
INSERT INTO "schema_migrations" (version) VALUES
  ('20220818223405');
```

Now test the schema file, it should be possible to use on an empty db to initialise it.

Run `sqlite3 test2.db`

```
SQLite version 3.39.....
Enter ".help" for usage hints.
sqlite> .read db/schema.sql
Parse error near line 5: object name reserved for internal use: sqlite_sequence
```

## Solution

The table `sqlite_sequence` should not be extracted in the schema, sqlite will generate it automatically.
