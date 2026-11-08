JSON
Hey,

I was playing around ramsql today and I've got a json column

```
db, err = sql.Open("ramsql", "store")
if err != nil {
	panic(fmt.Sprintf("sql.Open : Error : %s\n", err))
}
db.Exec(`CREATE TABLE test (sequence_number BIGSERIAL PRIMARY KEY, aggregate_id UUID, type TEXT, data JSON, created_at TIMESTAMP);`)
```

Insertion seems to work but unfortunately everything I put into the data column gets an extra level of escaping when I retrieve it for example:
`{\"id\":\"c05d13bd-9d9b-4ea1-95f2-9b11ed3a7d38\",\"name\":\"\"}`

Which breaks the json.Unmarshal process.  This behaviour isn't consistent with postgresql.

### Additional contract requirements

- When JSON is inserted as a byte array, selecting the value and scanning it into a string must return exactly the same text, byte for byte, as the inserted JSON.
