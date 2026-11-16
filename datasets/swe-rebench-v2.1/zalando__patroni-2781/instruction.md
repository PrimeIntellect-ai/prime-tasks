allow-group-access clause in initdb seems not woking correctly
**Describe the bug**
When using allow-group-access clause in initdb still have some files stlil created with 600 permisstions
```
find /data/postgresql/11/data/ -type f  -perm 600
/data/postgresql/11/data/patroni.dynamic.json
/data/postgresql/11/data/postgresql.base.conf.backup
/data/postgresql/11/data/postgresql.conf.backup
/data/postgresql/11/data/recovery.done
```
As far as I know first 3 files are definitely created by patroni. recovery.* file also appears after restarting patroni daemon.

**To Reproduce**
1. Create patroni config with allow-group-access option
```
initdb:
    - allow-group-access
```
2. (Re)initialize cluster.
3. Observe file permissions in data directory.

**Expected behavior**
All files mast have group access permissions

**Environment**
- Patroni version: patroni 1.6.5
- PostgreSQL version: PostgreSQL 11.8 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 7.5.0-3ubuntu1~18.04) 7.5.0, 64-bit
- DCS (and its version): etcd Version: 3.2.17

I am not allowed to upgrade PostgreSQL and Patroni versions right now.

**Patroni configuration file**
Not sure it's needed. Please let me know if it is.

**patronictl show-config**
```
patronictl -c /etc/patroni/config.yml show-config
loop_wait: 10
maximum_lag_on_failover: 1048576
postgresql:
  parameters:
    max_connections: '200'
    max_locks_per_transaction: '64'
    max_prepared_transactions: '3'
    max_worker_processes: '1'
    track_commit_timestamp: false
    wal_level: replica
    wal_log_hints: true
  use_pg_rewind: true
  use_slots: true
retry_timeout: 10
ttl: 30
```

**Have you checked Patroni logs?**
Not sure it's needed. Please let me know if it is.

**Have you checked PostgreSQL logs?**
Not sure it's needed. Please let me know if it is.

**Have you tried to use GitHub issue search?**
Was unable to find anything usefull for allow-group-access

### Additional contract requirements

The permission helper is the module-level object `patroni.file_perm.pg_perm`, whose public method
`set_permissions_from_data_directory(data_dir)` returns `None`.

When the data directory cannot be inspected (for example `os.stat` raises), the helper must log an error
through the module logger using the message format `Can not check permissions on %s: %r`, passing the data
directory and the raised exception as the format arguments.

When applying the calculated umask fails, the helper must catch the exception and log an error through the
module logger using the message format `Can not set umask to %03o: %r`, passing the calculated mask and the
raised exception as the format arguments.
