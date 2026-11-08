BUG: operations with NPartitions not a power of 2 fails in some cases. BUG IN PARTITON_MANAGER?. possible solution in here!
### Modin version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the latest released version of Modin.

- [ ] I have confirmed this bug exists on the main branch of Modin. (In order to do this you can follow [this guide](https://modin.readthedocs.io/en/stable/getting_started/installation.html#installing-from-the-github-main-branch).)


### Reproducible Example

I was am really struggling creating a reproducer, all the data I create does not lead to the error.
I will further try to find artificial data that works.

I have a pointcloud that I save in 75 partitions to parquets

When I load it again (using a fresh process), i get issues

```py

with context(NPartitions=75):
    df = pd.read_parquet(r'input_output/20240904-081345/preprocessor_poloplast_0-0-0.parquet')
print(df.max())
```

leads to

```
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/partitioning/partition_manager.py", line 873, in map_partitions_joined_by_column
    result[i : i + step, j] = joined_column_partitions[j].apply(
    ~~~~~~^^^^^^^^^^^^^^^^^
ValueError: could not broadcast input array from shape (2,) into shape (1,)
```


```py

with context(NPartitions=50):
    df = pd.read_parquet(r'input_output/20240904-081345/preprocessor_poloplast_0-0-0.parquet')
print(df.max())
```
works fine


Setting MinColumnsPerPartition to something larger then the amount of columns I have (its just 15 columns) nothing changes.



### Issue Description

using partitions numbers that are no power of 2 can lead to issues. Details below

### Expected Behavior

I would like the operations to not fail with the given error

### Error Logs

<details>

```python-traceback

Traceback (most recent call last):
  File "/home/cirqular/PycharmProjects/cirqular_mono_repo/archive/debug.py", line 42, in <module>
    df = pd.read_parquet(r'input_output/20240904-081345/preprocessor_poloplast_0-0-0.parquet')
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/utils.py", line 591, in wrapped
    return func(*params.args, **params.kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/logging/logger_decorator.py", line 144, in run_and_log
    return obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/pandas/io.py", line 325, in read_parquet
    query_compiler=FactoryDispatcher.read_parquet(
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/execution/dispatching/factories/dispatcher.py", line 202, in read_parquet
    return cls.get_factory()._read_parquet(**kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/execution/dispatching/factories/factories.py", line 257, in _read_parquet
    return cls.io_cls.read_parquet(**kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/logging/logger_decorator.py", line 144, in run_and_log
    return obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/io/file_dispatcher.py", line 165, in read
    if not AsyncReadMode.get() and hasattr(query_compiler, "dtypes"):
                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/storage_formats/pandas/query_compiler.py", line 329, in dtypes
    return self._modin_frame.dtypes
           ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/dataframe/dataframe.py", line 424, in dtypes
    dtypes = self._dtypes.get()
             ^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/metadata/dtypes.py", line 928, in get
    self._value = self._value.to_series()
                  ^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/metadata/dtypes.py", line 440, in to_series
    self.materialize()
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/metadata/dtypes.py", line 405, in materialize
    self._materialize_cols_with_unknown_dtypes()
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/metadata/dtypes.py", line 391, in _materialize_cols_with_unknown_dtypes
    self._known_dtypes.update(self._parent_df._compute_dtypes(subset))
                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/logging/logger_decorator.py", line 144, in run_and_log
    return obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/dataframe/dataframe.py", line 480, in _compute_dtypes
    obj.tree_reduce(0, lambda df: df.dtypes, dtype_builder)
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/logging/logger_decorator.py", line 144, in run_and_log
    return obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/dataframe/utils.py", line 753, in run_f_on_minimally_updated_metadata
    result = f(self, *args, **kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/dataframe/dataframe.py", line 2217, in tree_reduce
    map_parts = self._partition_mgr_cls.map_partitions(self._partitions, map_func)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/execution/modin_aqp.py", line 165, in magic
    result_parts = f(*args, **kwargs)
                   ^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/logging/logger_decorator.py", line 144, in run_and_log
    return obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/partitioning/partition_manager.py", line 73, in wait
    result = func(cls, *args, **kwargs)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/partitioning/partition_manager.py", line 698, in map_partitions
    new_partitions = cls.map_partitions_joined_by_column(
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/logging/logger_decorator.py", line 144, in run_and_log
    return obj(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^
  File "/home/cirqular/anaconda3/envs/lightning/lib/python3.11/site-packages/modin/core/dataframe/pandas/partitioning/partition_manager.py", line 873, in map_partitions_joined_by_column
    result[i : i + step, j] = joined_column_partitions[j].apply(
    ~~~~~~^^^^^^^^^^^^^^^^^
ValueError: could not broadcast input array from shape (2,) into shape (1,)
```

</details>


### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : c8bbca8e4e00c681370e3736b2f73bb0352408c3
python                : 3.11.9.final.0
python-bits           : 64
OS                    : Linux
OS-release            : 6.8.0-40-generic
Version               : #40~22.04.3-Ubuntu SMP PREEMPT_DYNAMIC Tue Jul 30 17:30:19 UTC 2
machine               : x86_64
processor             : x86_64
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8
Modin dependencies
------------------
modin                 : 0.31.0
ray                   : 2.24.0
dask                  : 2024.6.0
distributed           : 2024.6.0
pandas dependencies
-------------------
pandas                : 2.2.2
numpy                 : 1.26.3
pytz                  : 2024.1
dateutil              : 2.9.0.post0
setuptools            : 69.5.1
pip                   : 24.1.2
Cython                : None
pytest                : None
hypothesis            : None
sphinx                : None
blosc                 : None
feather               : None
xlsxwriter            : None
lxml.etree            : None
html5lib              : None
pymysql               : None
psycopg2              : None
jinja2                : 3.1.3
IPython               : 8.25.0
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : 2024.2.0
gcsfs                 : None
matplotlib            : 3.8.4
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
pyarrow               : 16.1.0
pyreadstat            : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.14.0
sqlalchemy            : 2.0.32
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
zstandard             : None
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None
</details>
