[feature request] INSERT IGNORE
Please add the option of using 'INSERT IGNORE', right now all insertions are just 'INSERT'.

### Additional contract requirements

- Insert queries can be switched to the ignore form through a chainable method named `ignore()` on the query builder (for example `Query.into(table).insert(1).ignore()`, or the same call after `.from_(...).select(...)` for an insert-from-select query).
- When `ignore()` is applied, the generated statement uses the keyword form `INSERT IGNORE INTO ...` in place of `INSERT INTO ...`; for example `INSERT IGNORE INTO "abc" VALUES (1)`.
- Without `ignore()`, insert statements are rendered exactly as before (`INSERT INTO ...`).
