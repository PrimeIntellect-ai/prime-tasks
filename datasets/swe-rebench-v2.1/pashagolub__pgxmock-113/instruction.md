.Scan() panics if a time.Time mock value is scanned into a sql.NullTime
**Describe the bug**
rowSets.Scan() tries to use reflect.Set to scan from one struct to another, regardless of whether they're compatible.

**To Reproduce**
Steps to reproduce the behavior:

```
        mock.ExpectQuery(`SELECT now()`).
		WillReturnRows(
			mock.NewRows([]string{"stamp"}).
				AddRow(time.Now()))

	var value sql.NullTime
	err: = mock.QueryRow(context.Background(), `SELECT now()`).Scan(&value)
```

I would expect the sql.NullTime value be set to time.Now().

Instead it panics during the Scan, with

```
panic: reflect.Set: value of type time.Time is not assignable to type sql.NullTime [recovered]
	panic: reflect.Set: value of type time.Time is not assignable to type sql.NullTime
```

and a stack trace pointing at [pgxmock/rows.go:92](https://github.com/pashagolub/pgxmock/blob/9be33e0f1925a8572f2deae43e09a513859db1c9/rows.go#L92)

I don't think comparing Kind() is enough to decide that a value is assignable. [HIDDEN]

### Additional contract requirements

- Scanning a returned `time.Time` value into `sql.NullTime` must complete without a panic or error and assign the returned timestamp to the destination.
