`'skein.crt' file already exists, use `force` to overwrite` error
I have been running multiple Dask-Yarn cluster applications on EMR. I am now getting this error when trying to start a new cluster application:

```
2019-02-21 23:09:05,489 [ERROR] __main__.forecast_: 'skein.crt' file already exists, use `force` to overwrite
Traceback (most recent call last):
 File "/usr/local/azkaban_projects/ovforecast/projects/de_ghd_ovf/forecast/ovf.py", line 302, in forecast_
   testset, custom_group_file, use_yarn=use_yarn)
 File "/usr/local/lib/python2.7/site-packages/ovforecast/forecast.py", line 87, in forecast
   yarn_app_name=app_name)
 File "/usr/local/lib/python2.7/site-packages/functools32/functools32.py", line 400, in wrapper
   result = user_function(*args, **kwds)
 File "/usr/local/lib/python2.7/site-packages/ovforecast/yarn.py", line 274, in get_dask_cluster
   cluster = YarnCluster.from_specification(spec)
 File "/usr/local/lib/python2.7/site-packages/dask_yarn/core.py", line 325, in from_specification
   self._start_cluster(spec, skein_client)
 File "/usr/local/lib/python2.7/site-packages/dask_yarn/core.py", line 335, in _start_cluster
   skein_client = _get_skein_client(skein_client)
 File "/usr/local/lib/python2.7/site-packages/dask_yarn/core.py", line 44, in _get_skein_client
   return skein.Client(security=security)
 File "/usr/local/lib/python2.7/site-packages/skein/core.py", line 326, in __init__
   security = Security.from_default()
 File "/usr/local/lib/python2.7/site-packages/skein/model.py", line 342, in from_default
   return cls.new_credentials().to_directory(directory=properties.config_dir)
 File "/usr/local/lib/python2.7/site-packages/skein/model.py", line 392, in to_directory
   raise context.FileExistsError(msg)
FileExistsError: 'skein.crt' file already exists, use `force` to overwrite
```

This error seems to have started when I moved to explicitly closing my Client and shuting down the cluster before my python application closes. My theory is that once one application closes and another is trying to start that the `skein.crt` file is being locked or not probably removed during shutdown?

My application is defined as:

```
worker = skein.Service(
instances=WORKER_INSTANCES,
max_restarts=-1,
resources=skein.Resources(
    memory=WORKER_MEMORY,
    vcores=WORKER_VCORES
),
files={
    './cachedvolume': skein.File(
        source='/mnt/tmp/cached_volume.sqlite3',
        type='file'
    )
},
env={'THEANO_FLAGS': 'base_compiledir=/tmp/.theano/',
     'WORKER_VOL_LOCATION': './cachedvolume',
     'PRESTO_URL': 'presto://{HOSTNAME}:8889'.format(
         HOSTNAME=os.environ.get('HOSTNAME')),
     'EC2_TEMPDIR': '/mnt/tmp',},
script='dask-yarn services worker',
depends=['dask.scheduler']
)

scheduler = skein.Service(
resources=skein.Resources(
    memory=SCHEDULER_MEMORY,
    vcores=SCHEDULER_VCORES
),
script='dask-yarn services scheduler'
)

spec = skein.ApplicationSpec(
name=yarn_app_name,
queue='default',
services={
    'dask.worker': worker,
    'dask.scheduler': scheduler
}
)
```

I am running Python 2.7 and
```
skein==0.5.1
dask==1.0.0
dask-yarn==0.5.0
```

### Additional contract requirements

- If multiple processes call `Security.from_default()` while credentials are initially absent, exactly one warning is emitted across those calls.
- Add a public function `lock_file(path)` in module `skein.utils`. It takes a filesystem path and returns a lock object. Calling `lock_file` with the same `path` returns the identical lock object.
- The returned lock object implements the context manager protocol and provides `acquire()` and `release()` methods.
- While the lock is held, other processes or threads attempting to acquire the same lock (the same `path`) block until it is released.
