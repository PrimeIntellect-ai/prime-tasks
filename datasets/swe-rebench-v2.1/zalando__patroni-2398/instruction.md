Accept *:port as a valid entry for postgresql.listen in patroni --validate-config
**Describe the bug**
If `postgresql.listen` is set to  `*:port`, `patroni --validate-config` complains.
I understand that security wise choosing the interface explicitly is better and that patroni's documentation
doesn't state that it's possible but it's a valid (and wide spread) postgresql.conf value.

If you're ok with allowing this, we can do the PR.

**To Reproduce**
1 ) configure `postgresql.listen` to `*:5432` in the yaml
2 ) run `patroni --validate-config` on the config file

**Expected behavior**
No errors.

**Screenshots**
```
postgresql.listen *:5432 didn't pass validation: gaierror(-2, 'Name or service not known')
```

**Environment**
- Patroni version: 2.1.4
- PostgreSQL version: 14.5
- DCS (and its version): 3.4.20

**Patroni configuration file**
```
scope: pgdemo
name: pg1
bootstrap:
  dcs:
    postgresql:
      parameters:
        cluster_name: pg1
        lc_messages: C
        lc_monetary: C
        lc_numeric: C
        lc_time: C
        listen_addresses: '*'
        log_destination: stderr
        logging_collector: true
        port: 5432
        unix_socket_directories: /run/user/1000/pglift/postgresql
  initdb:
  - locale: C
  - encoding: UTF8
  pg_hba:
  - local   all             postgres                                trust
  - local   all             all                                     trust
  - host    all             all             127.0.0.1/32            trust
  - host    all             all             ::1/128                 trust
  - local   replication     replication                              trust
  - host    replication     replication      127.0.0.1/32            trust
  - host    replication     replication      ::1/128                 trust
  pg_ident:
  - '# MAPNAME       SYSTEM-USERNAME         PG-USERNAME'
restapi:
  connect_address: 127.0.1.1:8008
  listen: 127.0.1.1:8008
etcd3:
  host: 10.20.60.99:2379
postgresql:
  authentication:
    superuser:
      username: postgres
    replication:
      username: replication
    rewind:
      username: postgres
  connect_address: 127.0.1.1:5432
  data_dir: /home/vagrant/.local/share/pglift/srv/pgsql/14/pg1/data
  bin_dir: /usr/pgsql-14/bin
  listen: 127.0.1.1:5432
  use_unix_socket: true
  use_unix_socket_repl: true
  pgpass: /home/vagrant/.pgpass
  parameters:
    cluster_name: pg1
    lc_messages: C
    lc_monetary: C
    lc_numeric: C
    lc_time: C
    listen_addresses: '*'
    log_destination: stderr
    logging_collector: true
    port: 5432
    unix_socket_directories: /run/user/1000/pglift/postgresql
  pg_hba:
  - local   all             postgres                                trust
  - local   all             all                                     trust
  - host    all             all             127.0.0.1/32            trust
  - host    all             all             ::1/128                 trust
  - local   replication     replication                              trust
  - host    replication     replication      127.0.0.1/32            trust
  - host    replication     replication      ::1/128                 trust
  pg_ident:
  - '# MAPNAME       SYSTEM-USERNAME         PG-USERNAME'
```

**patronictl show-config**
```
(.venv) [vagrant@pat1 pglift]$ patronictl show-config
postgresql:
  parameters:
    cluster_name: pg1
    lc_messages: C
    lc_monetary: C
    lc_numeric: C
    lc_time: C
    listen_addresses: '*'
    log_destination: stderr
    logging_collector: true
    port: 5432
    unix_socket_directories: /run/user/1000/pglift/postgresql
```

**Have you checked Patroni logs?**
N/A

**Have you checked PostgreSQL logs?**
N/A

**Have you tried to use GitHub issue search?**
I didn't find one.

**Additional context**
N/A
