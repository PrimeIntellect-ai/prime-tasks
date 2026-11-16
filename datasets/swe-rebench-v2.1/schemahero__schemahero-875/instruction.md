Cassandra support appears broken
On a fresh schemahero install of v0.13.8, I'm noticing an error in the controller pod for my cassandra database:
```
manager {"level":"error","msg":"unable to deploy table to connection of different type"}
```

The following are my database and table definitions:
```yaml
---
# https://schemahero.io/docs/connecting-databases/creating-db-resource/

apiVersion: databases.schemahero.io/v1alpha4
kind: Database
metadata:
  name: cassandra-testdb
spec:
  connection:
    cassandra:
      hosts: [ ... ] # omitted
      keyspace:
        valueFrom:
          secretKeyRef:
            name: db-credentials-schema-hero-example-secret
            key: /example/keyspace
      username:
        valueFrom:
          secretKeyRef:
            name: db-credentials-schema-hero-example-secret
            key: /example/db-username
      password:
        valueFrom:
          secretKeyRef:
            name: db-credentials-schema-hero-example-secret
            key: /example/db-password

---
apiVersion: schemas.schemahero.io/v1alpha4
kind: Table
metadata:
  name: players
spec:
  database: cassandra-testdb
  name: players
  schema:
    cassandra:
      primaryKey:
        - [id]
      columns:
        - name: id
          type: varchar
```

Reading the source code, I believe this is where the error is coming from:
https://github.com/schemahero/schemahero/blob/fa83f6214bea133a4d0947423d68f8adf6630a6a/pkg/controller/table/reconcile_table.go#L61-L65

and the failing conditional is driven by this function which appears to lack cassandra support:
https://github.com/schemahero/schemahero/blob/fa83f6214bea133a4d0947423d68f8adf6630a6a/pkg/controller/table/reconcile_table.go#L141-L157

I'm new to schemahero and just exploring its capabilities. Please let me know if there's anything that I've overlooked, and thanks for the great work on this tool otherwise!

### Additional contract requirements

The database-type compatibility check is exposed as `checkDatabaseTypeMatches(connection *databasesv1alpha4.DatabaseConnection, tableSchema *schemasv1alpha4.TableSchema) bool` in package `pkg/controller/table`. It returns `true` when the connection and the table schema both specify the same database type, including Cassandra, and `false` when they specify different database types, including a Cassandra connection paired with a non-Cassandra schema.
