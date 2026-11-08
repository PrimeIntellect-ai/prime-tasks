b2.api.B2Api.get_bucket_by_name does not work with bucket-scoped application keys
I am using Duplicity 0.7.17 and b2 1.3.2.

duplicity is executed using

```
duplicity \
    --verbosity debug \
    /backup \
    "b2://$B2_APP_KEY_ID:$B2_APP_KEY@$B2_BUCKET_NAME"
```

Where `$B2_APP_KEY_ID` and `$B2_APP_KEY` are URL-encoded strings which were output from a call to:

```
b2 create-key \
    --bucket "$B2_BUCKET_NAME" \
    "$B2_KEY_NAME" \
    listFiles,readFiles,writeFiles,deleteFiles,listBuckets
```

Duplicity fails with the following traceback:

```
Traceback (innermost last):
  File "/usr/local/bin/duplicity", line 1555, in <module>
    with_tempdir(main)
  File "/usr/local/bin/duplicity", line 1541, in with_tempdir
    fn()
  File "/usr/local/bin/duplicity", line 1380, in main
    action = commandline.ProcessCommandLine(sys.argv[1:])
  File "/usr/local/lib/python2.7/dist-packages/duplicity/commandline.py", line 1135, in ProcessCommandLine
    backup, local_pathname = set_backend(args[0], args[1])
  File "/usr/local/lib/python2.7/dist-packages/duplicity/commandline.py", line 1010, in set_backend
    globals.backend = backend.get_backend(bend)
  File "/usr/local/lib/python2.7/dist-packages/duplicity/backend.py", line 223, in get_backend
    obj = get_backend_object(url_string)
  File "/usr/local/lib/python2.7/dist-packages/duplicity/backend.py", line 209, in get_backend_object
    return factory(pu)
  File "/usr/local/lib/python2.7/dist-packages/duplicity/backends/b2backend.py", line 87, in __init__
    self.bucket = self.service.get_bucket_by_name(bucket_name)
  File "/usr/local/lib/python2.7/dist-packages/b2/api.py", line 222, in get_bucket_by_name
    [HIDDEN]
  File "/usr/local/lib/python2.7/dist-packages/logfury/v0_1/trace_call.py", line 84, in wrapper
    return function(*wrapee_args, **wrapee_kwargs)
  File "/usr/local/lib/python2.7/dist-packages/b2/api.py", line 251, in list_buckets
    self.check_bucket_restrictions(bucket_name)
  File "/usr/local/lib/python2.7/dist-packages/logfury/v0_1/trace_call.py", line 84, in wrapper
    return function(*wrapee_args, **wrapee_kwargs)
  File "/usr/local/lib/python2.7/dist-packages/b2/api.py", line 375, in check_bucket_restrictions
    raise RestrictedBucket(allowed_bucket_name)
 RestrictedBucket: Application key is restricted to bucket: pc-backup
```

Internally<sup>[[1]](https://bazaar.launchpad.net/~duplicity-team/duplicity/0.8-series/view/head:/duplicity/backends/b2backend.py#L88)</sup>, Duplicity uses `b2.api.B2Api.get_bucket_by_name`, passing in the name of the bucket. [HIDDEN]

This looks related to changes in #474.

### Additional contract requirements

- Looking up a bucket by name with a bucket-scoped application key must succeed when the requested bucket is the one permitted by that key.
