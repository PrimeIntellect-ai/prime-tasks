Can not run archive command containing shell operators
### What happened?

if use shell operators(`&&` or `|`) in `archive_command`, `archive_ready_wals` will fail [HIDDEN]

Just for example, set archive_command='sleep 20 && /bin/false':
```
2023-07-18 18:32:34,071 INFO: Trying to archive 00000001000000000000002F: sleep 20 && /bin/false
sleep: invalid time interval ‘&&’
sleep: invalid time interval ‘/bin/false’
Try 'sleep --help' for more information.
2023-07-18 18:32:34,075 INFO: Failed to archive WAL segment 00000001000000000000002F
```


### How can we reproduce it (as minimally and precisely as possible)?

-

### What did you expect to happen?

Using shell operators in `archive_command` is a common practice since the doc definition of `archive_command` is a shell command, such as:
```
archive_command = 'test ! -f /mnt/server/archivedir/%f && cp %p /mnt/server/archivedir/%f'  # Unix
```

[HIDDEN]

I am happy to provide help.

### Patroni/PostgreSQL/DCS version

-   Patroni version: 3.0.4
-   PostgreSQL version: 14
-   DCS (and its version): kubernetes


### Patroni configuration file

```yaml
-
```


### patronictl show-config

```yaml
-
```


### Patroni log files

```shell
-
```


### PostgreSQL log files

```shell
-
```


### Have you tried to use GitHub issue search?

- [X] Yes

### Anything else we need to know?

_No response_

### Additional contract requirements

- When `archive_command` contains shell operators such as `&&` or `|`, those operators must be interpreted as shell syntax so command chaining and pipelines work as intended.
