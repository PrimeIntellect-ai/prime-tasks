Unable to set up replica nodes after converting leader from standalone
**Describe the bug**
Was able to set up leader, but not the replica nodes when converting standalone installation to patroni.

**To Reproduce**
Steps to reproduce the behavior:
Follow https://patroni.readthedocs.io/en/latest/existing_data.html and add replica node.
Even added the rewind user according to https://www.postgresql.org/docs/13/app-pgrewind.html

**Expected behavior**
Replica to work.

**Environment**
- Patroni version: 2.1.3
- PostgreSQL version: 13.5.1PGDG.rhel7
- DCS (and its version): etcd3

**Patroni configuration file**
```
scope: cluster
name: pg2

log:
  level: WARNING
  format: '%(levelname)s: %(message)s'
  loggers:
    patroni.postmaster: WARNING
    urllib3: INFO

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.2.3:8008

etcd:
  hosts: 192.168.2.21:2379,192.168.2.22:2379,192.168.2.23:2379
  protocol: https
  cacert: /etc/patroni/etcd/ca.crt
  cert: /etc/patroni/etcd/client.crt
  key: /etc/patroni/etcd/client.key
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        log_destination: syslog
        log_line_prefix: ''
        max_connections: 100

  initdb:
  - encoding: UTF8
  - data-checksums

  pg_hba:
  - host replication replicator 192.168.2.2/32 scram-sha-256
  - host replication replicator 192.168.2.3/32 scram-sha-256
  - host replication replicator 192.168.2.4/32 scram-sha-256
  - host replication replicator 192.168.2.5/32 scram-sha-256
  - host all rewind_user 192.168.2.0/24 scram-sha-256
  - host all patroni 192.168.2.0/24 scram-sha-256

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.2.3:5432
  data_dir: /var/lib/pgsql/13/data
  bin_dir: /usr/pgsql-13/bin
  pgpass: /var/lib/pgsql/.pgpass
  authentication:
    superuser:
      username: patroni
      password: superuserpass
    replication:
      username: replicator
      password: replicatorpass
    rewind:
      username: rewind_user
      password: rewindpass

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: true
    nosync: false
```

**patronictl show-config**
On that machine it is unable to show it, but might be due to not getting set up. On leader:
```
loop_wait: 10
maximum_lag_on_failover: 1048576
postgresql:
  parameters:
    log_destination: syslog
    log_line_prefix: ''
    max_connections: 100
  pg_hba:
  - local   all             all                                     peer
  - '# IPv4 local connections:'
  - host    all             all             127.0.0.1/32            scram-sha-256
  - '# IPv6 local connections:'
  - host    all             all             ::1/128                 scram-sha-256
  - '# Allow replication connections from localhost, by a user with the'
  - '# replication privilege.'
  - local   replication     all                                     peer
  - host    replication     all             127.0.0.1/32            scram-sha-256
  - host    replication     all             ::1/128                 scram-sha-256
  - ''
  - '# Patroni'
  - host    replication     replicator      192.168.2.2/32          scram-sha-256
  - host    replication     replicator      192.168.2.3/32          scram-sha-256
  - host    replication     replicator      192.168.2.4/32          scram-sha-256
  - host    replication     replicator      192.168.2.5/32          scram-sha-256
  - host    all             rewind_user     192.168.2.0/24          scram-sha-256
  - host    all             patroni         192.168.2.0/24          scram-sha-256
  use_pg_rewind: true
  use_slots: true
retry_timeout: 10
ttl: 30
```

**Have you checked Patroni logs?**
```
Mar 31 15:41:09 pg2.my.intra patroni[5596]: ERROR: Exception when working with leader
Mar 31 15:41:09 pg2.my.intra patroni[5596]: Traceback (most recent call last):
Mar 31 15:41:09 pg2.my.intra patroni[5596]: File "/usr/lib/python3.6/site-packages/patroni/postgresql/rewind.py", line 60, in check_leader_is_not_in_recovery
Mar 31 15:41:09 pg2.my.intra patroni[5596]: with get_connection_cursor(connect_timeout=3, options='-c statement_timeout=2000', **conn_kwargs) as cur:
Mar 31 15:41:09 pg2.my.intra patroni[5596]: File "/usr/lib64/python3.6/contextlib.py", line 81, in __enter__
Mar 31 15:41:09 pg2.my.intra patroni[5596]: return next(self.gen)
Mar 31 15:41:09 pg2.my.intra patroni[5596]: File "/usr/lib/python3.6/site-packages/patroni/postgresql/connection.py", line 44, in get_connection_cursor
Mar 31 15:41:09 pg2.my.intra patroni[5596]: conn = psycopg.connect(**kwargs)
Mar 31 15:41:09 pg2.my.intra patroni[5596]: File "/usr/lib64/python3.6/site-packages/psycopg2/__init__.py", line 127, in connect
Mar 31 15:41:09 pg2.my.intra patroni[5596]: conn = _connect(dsn, connection_factory=connection_factory, **kwasync)
Mar 31 15:41:09 pg2.my.intra patroni[5596]: psycopg2.OperationalError: FATAL:  no pg_hba.conf entry for host "192.168.2.3", user "replicator", database "postgres", SSL off
```

**Have you checked PostgreSQL logs?**
On Leader:
```
2022-03-31T15:41:09.067491+03:00 local0:err pg1.my.intra postgres[117034]:  [10-1] FATAL:  no pg_hba.conf entry for host "192.168.2.3", user "replicator", database "postgres", SSL off
2022-03-31T15:41:09.067874+03:00 local0:err pg1.my.intra postgres[117034]:  [10-2] DETAIL:  Client IP address resolved to "pg2.my.intra", forward lookup not checked.
```

**Have you tried to use GitHub issue search?**

Yes...

#2257 Issue seems to relate to the same issue, however the instructions for converting standalone do not have any reference to pg_hba config guidelines and no notice of having to give replica user access to postgres db. Nor does any sample config file include in bootstrap the access required. `host all all 0.0.0.0/0 md5` is clearly way too much.
Might be also related to change in #2162.

**Additional context**

Error itself is quite cryptic if you are trying to set up the cluster. The documentation doesn't seem to state that you need to give replication user access to postgres db. Such access is not needed for replication itself, but should be duties of some sort of "control user". Makes me wonder why superuser is even used, if it is not used for that purpose.

Checking the documentation, then it mentions only `- host replication replicator 127.0.0.1/32 md5: A line like this is required for replication.` in https://github.com/zalando/patroni/blob/master/docs/SETTINGS.rst

It seems a lot more work to fix all the documentation rather than make it work on some other user than replication user. Like a lot of people requested in #2257.

### Additional contract requirements

- A replica must be able to join a cluster that was converted from a standalone server without the replication user having ordinary access to the `postgres` database, as long as a separate non-replication control or rewind credential is configured (`authentication.rewind`) and `use_pg_rewind` is enabled. The check that the leader is not in recovery must then succeed using that credential rather than the replication user.
