Support for pgxpool Stat() in PgxPoolIface
**Is your feature request related to a problem? Please describe.**
pgx/pool.go https://github.com/jackc/pgx/blob/847f888631e7356f88766bcb4986afd3c4b8fd76/pgxpool/pool.go#L557 has a Stat feature for pool connection information that I would like to use.  Since the PgxPoolIface mock interface does not support this I am unable to implement this.

**Describe the solution you'd like**
Support for Stat() *pgxpool.Stat added to the PgxPoolIface interface.

**Describe alternatives you've considered**
none

**Additional context**
none
