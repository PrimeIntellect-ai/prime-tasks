`fsstats` no longer matches output of `fsdump`
ZODB==5.6.0

`scripts.fsstats` is supposed to derive statistics from the output of `FileStorage.fsdump`. However, it no longer understands this output.

Transaction records produced by `fsdump` look like
```
Trans #00000 tid=038e1d5f01b145cc time=2011-05-05 07:59:00.396673 offset=70
    status='p' user='' description='Created Zope Application\n\nAdded temp_folder'
```
and data records like
```
  data #00000 oid=0000000000000006 size=141 class=Products.ZODBMountPoint.MountedObject.MountedObject
```
but `fsstats` [HIDDEN].

### Additional contract requirements

- `ZODB.FileStorage.fsdump` must be runnable as a module, so that
  `python -m ZODB.FileStorage.fsdump <path>` writes the dump of the storage at
  `<path>` to standard output.
- Transaction lines in the `fsdump` output must include the size of the transaction
  in bytes, and `fsstats` must report the transaction sizes of all transactions
  in the dump.
- `fsstats` must take every data record in the dump into account: its object size
  and per-class statistics must cover all of the records.
