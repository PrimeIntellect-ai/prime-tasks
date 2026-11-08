Add support for pg_vector
https://github.com/pgvector/pgvector/tree/master

This is a new type for postgres, it's parameterized

### Additional contract requirements

PostgreSQL schema changes must accept parameterized pgvector column types and retain each declared dimension in the SQL generated for that column.
