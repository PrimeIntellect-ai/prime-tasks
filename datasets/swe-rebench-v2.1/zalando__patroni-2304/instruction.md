Removed data directory
**Describe the bug**
We had networking issues and Patroni switched the primary sql server multiple times (40+).
The timelines diverged and the following was in the log files:

2022-05-15 14:13:05,019 INFO: reinitializing due to diverged timelines
2022-05-15 14:13:08,613 INFO: Removing data directory: /var/lib/pgsql/13/data

We don't have the following parameters set in any configuration:

remove_data_directory_on_rewind_failure
remove_data_directory_on_diverged_timelines

And by default, the values should be 'false' according to https://patroni.readthedocs.io/en/latest/SETTINGS.html#postgresql

**Expected behavior**
Data directory should not be removed since "remove_data_directory_on_diverged_timelines" is not set

**Environment**
- Patroni version: 2.1.3
- PostgreSQL version: 13.5
- DCS (and its version): etcd 3.5.2

**Patroni configuration file**
```
scope: 'patroni_env'
namespace: '/patroni/'
name: 'envdb2'

log:
  dir: '/var/log/pgsql/'
  file_size: 2097152
  file_num: 5

restapi:
  listen: '192.168.1.12:8008'
  connect_address: '192.168.1.12:8008'
#  certfile: /etc/ssl/certs/ssl-cert.pem
#  keyfile: /etc/ssl/private/ssl-cert.key
#  authentication:
#    username: username
#    password: password

# ctl:
#   insecure: false # Allow connections to SSL sites without certs
#   certfile: /etc/ssl/certs/ssl-cert.pem
#   cacert: /etc/ssl/certs/ssl-cacert.pem

etcd:
  hosts: "192.168.1.10:2379,192.168.1.12:2379,192.168.1.2:2379,192.168.1.3:2379,192.168.1.6:2379,192.168.1.7:2379"
  protocol: http
#  cacert: /etc/patroni/certs/ca.crt
#  cert: /etc/patroni/certs/client.crt
#  key: /etc/patroni/certs/client.key

bootstrap:
  # this section will be written into Etcd:/<namespace>/<scope>/config after initializing new cluster
  # and all other cluster members will use it as a `global configuration`
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 536870912
#    master_start_timeout: 300
#    synchronous_mode: false
    #standby_cluster:
      #host: 127.0.0.1
      #port: 1111
      #primary_slot_name: patroni
    postgresql:
      use_pg_rewind: true
#      use_slots: true
      parameters:
         max_locks_per_transaction: 2000
         wal_log_hints: on
         hot_standby: on
         max_connections: 150
         wal_keep_size: 5120MB
         max_replication_slots: 5
         max_wal_senders: 10

  # some desired options for 'initdb'
#  initdb:  # Note: It needs to be a list (some options need values, others are switches)
#  - encoding: UTF8
#  - data-checksums

#  pg_hba:  # Add following lines to pg_hba.conf after running 'initdb'
#  - local   all             all                                     peer
#  - host    all             all             127.0.0.1/32            md5
#  - host    all             all             ::1/128                 ident
#  - host    all             all             0.0.0.0/0               md5
#  - host    all             all             ::0/0                   md5
#  - host    replication     replication     0.0.0.0/0               md5
#  - host    replication     replication     ::0/0                   md5

  # Additional script to be launched after initial cluster creation (will be passed the connection URL as parameter)
# post_init: /usr/local/bin/setup_cluster.sh

  # Some additional users users which needs to be created after initializing new cluster
#  users:
#    admin:
#      password: admin
#      options:
#        - createrole

postgresql:
  listen: '*:5432'
  connect_address: '192.168.1.12:5432'
  use_unix_socket: true
  data_dir: /var/lib/pgsql/13/data
  bin_dir: /usr/pgsql-13/bin
#  config_dir:
#pgpass_patroni is dynamically created on the replica during patroni start. Do not use the standard .pgpass file because it will overwrite the file
  pgpass: /var/lib/pgsql/.pgpass_patroni
  authentication:
    replication:
      username: replication
      password: PASSWORD
    superuser:
      username: postgres
      password: PASSWORD
  # Server side kerberos spn
#  krbsrvname: postgres
  parameters:
    unix_socket_directories: '/var/run/postgresql'

watchdog:
  mode: off # Allowed values: off, automatic, required
#  device: /dev/watchdog
#  safety_margin: 5

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
```

**patronictl show-config**
```
loop_wait: 10
maximum_lag_on_failover: 536870912
postgresql:
  parameters:
    hot_standby: true
    max_connections: 150
    max_locks_per_transaction: 2000
    max_replication_slots: 5
    max_wal_senders: 10
    wal_keep_size: 5120MB
    wal_log_hints: true
  use_pg_rewind: true
retry_timeout: 10
ttl: 30
```

**Have you checked Patroni logs?**
2022-05-15 14:13:05,019 INFO: reinitializing due to diverged timelines
2022-05-15 14:13:08,613 INFO: Removing data directory: /var/lib/pgsql/13/data

**Have you tried to use GitHub issue search?**
Yes
