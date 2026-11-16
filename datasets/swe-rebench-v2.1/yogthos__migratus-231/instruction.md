Sanitation of migration-table-name breaks existing migrations
```
$ lein --version
Leiningen 2.9.8 on Java 11.0.16 OpenJDK 64-Bit Server VM
$ clojure --version
Clojure CLI version 1.11.1.1155
$ psql --version
psql (PostgreSQL) 14.5 (Ubuntu 14.5-0ubuntu0.22.04.1)
```

My `:migration-table-name` is `"public.migratus"`. After updating from 1.3.3 to 1.4.4, migratus stripped it to be `publicmigratus`. This is a pretty big change and feels like it should have been highlighted in the changelog. If this change is permanent, can a new flag be added to not sanitize the table name?

https://github.com/yogthos/migratus/blob/fbb27047b0bae88af406e6c5a5eca565d653652b/src/migratus/database.clj#L37

[Originating PR](https://github.com/yogthos/migratus/pull/214)

### Additional contract requirements

The migration table name configured via `:migration-table-name` must be used verbatim, without sanitization or stripping of non-word characters. In particular, the schema-qualified name `public.migratus` must be preserved as `public.migratus` rather than collapsed to `publicmigratus`.
