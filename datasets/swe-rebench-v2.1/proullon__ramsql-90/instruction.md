"attribute not defined" error should state _which_ attribute it can't find
Started to get this error after upgrading from v0.0.1 to v0.1.0:

    "attribute not defined"

It would be helpful to indicate which attribute it missing, e.g.

    attribute not defined: attributeName

Bonus points if it were to also mention the table name, e.g.

    attribute not defined: table_name.attributeName

### Additional contract requirements

- For a query against `account` with the missing attribute `nope`, the error message must be exactly `attribute not defined: account.nope`.
