Subject filtered purge does not delete all data.
An easy way to test this is with object- seems to happen with big streams.

```
$ nats obj add BIGDATA
$  dd if=/dev/zero of=random.dat count=$((1024*1024)) bs=1024
$ nats obj put BIGDATA random.dat
$ nats s subjects OBJ_BIGDATA
        $O.BIGDATA.M.cmFuZG9tLmRhdA==: 1
  $O.BIGDATA.C.XeqSUUd063OcyuG9SAUx7u: 8,192
```

OK so we have a subject with 1 gig of data in it... lets purge it.

```
$ nats s purge OBJ_BIGDATA --subject '$O.BIGDATA.C.XeqSUUd063OcyuG9SAUx7u'
....
State:

             Messages: 64
                Bytes: 7.9 MiB
             FirstSeq: 63 @ 2022-10-06T17:42:41 UTC
              LastSeq: 8,193 @ 2022-10-06T17:42:45 UTC
     Deleted Messages: 8,067
     Active Consumers: 0
   Number of Subjects: 2
```

So thats too many messages, checking with `subjects`:

```
$ nats s subjects OBJ_BIGDATA
        $O.BIGDATA.M.cmFuZG9tLmRhdA==: 1
  $O.BIGDATA.C.XeqSUUd063OcyuG9SAUx7u: 63
```

All the data was not removed. Calling purge again will clear it.
