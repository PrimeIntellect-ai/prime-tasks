ExpectBatch() bug with unordered queries expectations
**Describe the bug**
A new funcionality with ExpectBatch() function doesn`t match Batch() expectation, when we are trying to follow expectations without straight order using pgxmock.MatchExpectationsInOrder(false).

**To Reproduce**
```go
func processBatch(db pgxmock.PgxPoolIface) error {
	batch := &pgx.Batch{}
        // Random order
	batch.Queue("SELECT id FROM normalized_queries WHERE query = $1", "some query")
	batch.Queue("INSERT INTO normalized_queries (query) VALUES ($1) RETURNING id", "some query")

	results := db.SendBatch(context.Background(), batch)
	defer results.Close()

	for i := 0; i < batch.Len(); i++ {
		var id int
		err := results.QueryRow().Scan(&id)
		if err != nil {
			return err
		}
	}

	return nil
}
```

```go
func TestProcessBatch(t *testing.T) {
	mock, err := pgxmock.NewPool()
	assert.NoError(t, err)
	defer mock.Close()

	mock.MatchExpectationsInOrder(false)

	expectedBatch := mock.ExpectBatch()
	expectedBatch.ExpectQuery(regexp.QuoteMeta("INSERT INTO normalized_queries (query) VALUES ($1) RETURNING id")).WithArgs("some query").
		WillReturnRows(pgxmock.NewRows([]string{"id"}).AddRow(10))
	expectedBatch.ExpectQuery(regexp.QuoteMeta("SELECT id FROM normalized_queries WHERE query = $1")).WithArgs("some query").
		WillReturnRows(pgxmock.NewRows([]string{"id"}).AddRow(20))

	err = processBatch(mock)
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
```

**Screenshot of the issue**
![image](https://github.com/pashagolub/pgxmock/assets/73113007/a42b957c-0d6b-4afb-8b0c-da0d5964afda)


**Expected behavior**
```go
func processBatch(db pgxmock.PgxPoolIface) error {
	batch := &pgx.Batch{}
        // Straight order
	batch.Queue("INSERT INTO normalized_queries (query) VALUES ($1) RETURNING id", "some query")
	batch.Queue("SELECT id FROM normalized_queries WHERE query = $1", "some query")

	results := db.SendBatch(context.Background(), batch)
	defer results.Close()

	for i := 0; i < batch.Len(); i++ {
		var id int
		err := results.QueryRow().Scan(&id)
		if err != nil {
			return err
		}
	}

	return nil
}
```

```go
func TestProcessBatch(t *testing.T) {
	mock, err := pgxmock.NewPool()
	assert.NoError(t, err)
	defer mock.Close()

	mock.MatchExpectationsInOrder(false)

	expectedBatch := mock.ExpectBatch()
	expectedBatch.ExpectQuery(regexp.QuoteMeta("INSERT INTO normalized_queries (query) VALUES ($1) RETURNING id")).WithArgs("some query").
		WillReturnRows(pgxmock.NewRows([]string{"id"}).AddRow(10))
	expectedBatch.ExpectQuery(regexp.QuoteMeta("SELECT id FROM normalized_queries WHERE query = $1")).WithArgs("some query").
		WillReturnRows(pgxmock.NewRows([]string{"id"}).AddRow(20))

	err = processBatch(mock)
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
```

**Screenshot of the expected behaviour**
![image](https://github.com/pashagolub/pgxmock/assets/73113007/bfbabfc0-ea08-4a72-ab3d-32be5474e38e)

**Desktop:**
 - OS: Windows 11
 - IDE: VS Code

### Additional contract requirements

- When `MatchExpectationsInOrder(false)` is active, batch queries must match their corresponding expectations regardless of the order in which the queries are queued and the expectations are declared. Each query must receive the result configured for its matching expectation.
