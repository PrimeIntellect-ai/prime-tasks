pgxpool.Pool does not implement BeginTxFunc required by pgxmock.PgxPoolIface
If I try to do something like this:
```
type Client struct {
	pool pgxmock.PgxPoolIface
}

func NewClient() *Client {
	pgUrl := "......"

	Pool, err := pgxpool.New(context.Background(), pgUrl)
	if err != nil {
		panic(err)
	}
	client := Client{pool}
	return &client
}
```

I get `cannot use Pool (variable of type *pgxpool.Pool) as type pgxmock.PgxPoolIface in struct literal: *pgxpool.Pool does not implement pgxmock.PgxPoolIface (missing BeginTxFunc method)`

The interface type provided by this package appears to be out of sync as https://github.com/jackc/pgx/blob/master/pgxpool/pool.go does not implement `BeginTxFunc` but `pgxmock.PgxPoolIface` inherits (or whatever it is called) it from `pgxmock.pgxIface`.

But I don't know, I am probably doing something wrong, I am a very inexperienced developer who is not mentally equipped to write go code.
