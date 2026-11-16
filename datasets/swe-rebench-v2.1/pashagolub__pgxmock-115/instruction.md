Matching query using WithArgs behavior.
If query in tested code got some arguments, but in test we do not use `.WithArgs`, or even providing no args with `.WithArgs()` it still matches query. Is it correct behavior? Or it should rise arguments do not match error, that shows that no arguments was expected but actually received some?
Example test passing:
```
func Test_QueryMatchingMissingWithArgs(t *testing.T) {
	mock, err := pgxmock.NewConn()
	if err != nil {
		t.Errorf("an error '%s' was not expected when opening a stub database connection", err)
	}

	mock.ExpectQuery("SELECT id FROM").WithArgs().WillReturnRows(pgxmock.NewRows([]string{"id"}).AddRow(1))

	var id int
	row := mock.QueryRow(context.Background(), "SELECT id FROM users WHERE name=$1", "john")
	err = row.Scan(&id)
	if err != nil {
		t.Errorf("error '%s' was not expected", err)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("there were unfulfilled expectations: %s", err)
	}
}
```

### Additional contract requirements

For query and execution expectations, omitting `WithArgs` or calling `WithArgs()` configures zero expected arguments. A call with zero arguments can match such an expectation when the other expectation criteria match. A call that supplies one or more arguments must fail to match that expectation as an argument mismatch.
