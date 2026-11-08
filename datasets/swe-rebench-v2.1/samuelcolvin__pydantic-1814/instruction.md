time ignores timedelta without error
# Bug

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
pydantic version: 1.5.1
pydantic compiled: True
install path: C:\...\.venv37\Lib\site-packages\pydantic
python version: 3.7.6 (tags/v3.7.6:43364a7ae0, Dec 19 2019, 00:42:30) [MSC v.1916 64 bit (AMD64)]
platform: Windows-10-10.0.17134-SP0
optional deps. installed: ['typing-extensions']
```

In the documentation at https://pydantic-docs.helpmanual.io/usage/types/#datetime-types it is stated that

> - time fields can be:
>    - time, existing time object
>    - str, following formats work:
>        - HH:MM[:SS[.ffffff]]

but as shown in the example below strings like `11:05+05:00`
- are accepted and raise no error
- loose the timedelta information

Loosing information (especially timedelta) without recognition can e.g. lead to discrepancies when collecting data from different sources and a relationship between single pieces of data must be established based on a timestamp.

I tried to track it down to the root cause:
```py
>>> from pydantic import datetime_parse

>>> incorrect_time = datetime_parse.parse_time("11:05+05:00")
>>> print(incorrect_time)
datetime.time(11, 5)
# Here I would expect to
# - either get an error because it is not stated that a format having a timedelta is accepted
# - or a datetime.time(11, 5, tzinfo=datetime.timezone(datetime.timedelta(seconds=18000)) as datetime.time.fromisoformat would return
```

### Additional contract requirements

- When an offset-bearing time string is rejected as unsupported, the error raised is `pydantic.errors.TimeError`.
