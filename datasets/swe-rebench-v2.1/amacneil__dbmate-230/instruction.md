postgres automatic peer auth
Currently, it's possible to connect to a database on localhost using a domain socket. For example:

```
$ dbmate -u "postgres:///database_name?socket=/var/run/postgresql" status
```

It'd be really nice if this was autodetected and you could just do:

```
$ dbmate -u postgres:///database_name status
```

The following works well on my machine:

```
$ psql postgres:///database_name
```

I believe that `psql` is using the `peer` authentication method on my local machine over the domain socket that postgres exposes.

Some more info:
https://www.postgresql.org/docs/current/auth-peer.html

### Additional contract requirements

- On Linux, a hostless PostgreSQL URL must default to the Unix socket host `/var/run/postgresql`; for example, the normalized connection string for `postgres:///foo` must be exactly `postgres://:5432/foo?host=%2Fvar%2Frun%2Fpostgresql`.
