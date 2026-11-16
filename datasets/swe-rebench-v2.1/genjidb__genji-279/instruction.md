Prevent creating a table if constraints are incoherent
```sql
CREATE TABLE foo (
  a INTEGER,
  a.b[0] TEXT
);
```

In this example, `a` is expected to be both an integer an a document, which is not possible. Detect these kind of incoherence and return an error.
