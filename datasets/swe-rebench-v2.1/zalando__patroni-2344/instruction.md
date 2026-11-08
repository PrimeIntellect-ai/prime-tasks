'patroni --validate-config' exists 0 upon invalid configuration
`patroni --validate-config` exists 0 upon invalid configuration:
```
$ patroni --validate-config postgres0.yml
restapi.connect_address 127.0.0.1:8008 didn't pass validation: 'must not contain "127.0.0.1", "0.0.0.0", "*", "::1", "localhost"'
etcd.host 127.0.0.1:2379 didn't pass validation: '127.0.0.1:2379 is not reachable'
postgresql.connect_address 127.0.0.1:5432 didn't pass validation: 'must not contain "127.0.0.1", "0.0.0.0", "*", "::1", "localhost"'
$ echo $?
0
```
This is misleading since one cannot rely on exit code to detect an error; also errors are printed to stdout whereas stderr would be more appropriate.
I'd suggest to:
* exit 1 upon invalid configuration
* print errors to stderr

and I'm willing to prepare a PR for this.

**Environment**
- Patroni version: master at b8a6387236d619345c2f72f2f8e858dc7a2bd791
- PostgreSQL version: n/a
- DCS (and its version): n/a
