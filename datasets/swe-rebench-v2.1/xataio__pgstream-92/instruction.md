Error when using a db that has dot (`.`) in the name
I'm using the `build` folder and [this article](https://xata.io/blog/postgres-webhooks-with-pgstream) as a guide.


When the database is called `example` it works correctly:
```
pgstream init --pgurl "postgres://postgres:postgres@db:5432/example?sslmode=disable"
```


When the database is called `example".com` it fails:
```
pgstream init --pgurl "postgres://postgres:postgres@db:5432/example.com?sslmode=disable"

ERROR   failed to create replication slot: ERROR: replication slot name "pgstream_example.com_slot" contains invalid character (SQLSTATE 42602)
Error: failed to create replication slot: ERROR: replication slot name "pgstream_example.com_slot" contains invalid character (SQLSTATE 42602)
```

And when I run the `pgstream` compose service I get this:

```
using config file: pg2webhook.env

   ____    __
  / __/___/ /  ___
 / _// __/ _ \/ _ \
/___/\__/_//_/\___/ v4.12.0
High performance, minimalist Go web framework
https://echo.labstack.com
____________________________________O/_______
                                    O\
⇨ http server started on [::]:9900
2024-12-01T08:30:05.254120391Z INF logger.go:37 > adding translation to processor...
2024-12-01T08:30:05.254173041Z INF logger.go:37 > running subscription server...
2024-12-01T08:30:05.254439849Z INF logger.go:37 > running postgres listener...
2024-12-01T08:30:05.25441942Z INF logger.go:37 > subscription server listening on: :9900... service=webhook_subscription_server
2024-12-01T08:30:05.254569887Z INF logger.go:37 > running webhook notifier...
2024-12-01T08:30:05.254794494Z INF logger.go:37 > replication handler: identifySystem success db_name=example.com position=14545114416 service=postgres_replication_handler slot_name=pgstream_example.com_slot system_id=7296245781040128039 timeline=1
Error: start replication: read last position: no rows in result set
```
