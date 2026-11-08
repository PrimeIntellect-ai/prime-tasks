`mix ecto.migrations` ignore the migrated versions while migration file is deleted
### Environment

* Elixir version (elixir -v): 1.5.2 (Erlang/OTP 20)
* Database and version (PostgreSQL 9.4, MongoDB 3.2, etc.): PostgreSQL 10.1
* Ecto version (mix deps): 2.2.7
* Database adapter and version (mix deps): postgrex 0.13.3
* Operating system: macOS

### Current behavior
After migrate the database, if any migration file is deleted, then `mix ecto.migrations` won't list corresponded migration, even though they're actually `:up` in the database.

To reporduce:
1. Generate a migration then run `mix ecto.migrate`
2. Delete the migration file
3. Run `mix ecto.migrations`
4. the report list is empty.
5. Check the `schema_migrations` table in database, there are actually one migration record there.

### Expected behavior

If the migration file is deleted, list them as :up with "FILE NOT FOUND" description
