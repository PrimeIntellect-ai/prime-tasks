DD_ENV (SERVICE, VERSION) are not used in ThreadStats
https://github.com/DataDog/datadogpy/pull/548 added support for taking unified tags from env vars, but it doesn't works when using ThreadStats in the following way:

```
>>> from datadog import initialize, ThreadStats
>>> initialize(api_key='my_api_key')
>>> stats = ThreadStats()
>>> stats.start()
```
