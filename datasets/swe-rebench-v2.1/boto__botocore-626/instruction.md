serialize._convert_header_value produces incorrect timestamp value when local timezone is not UTC
Current function definition:
```python
    def _convert_header_value(self, shape, value):
        if shape.type_name == 'timestamp':
            datetime_obj = parse_timestamp(value)
            timestamp = time.mktime(datetime_obj.timetuple())
            return self._timestamp_rfc822(timestamp)
        else:
            return value
```

If `value` is either `iso8601` or `rfc822` string with a zone specifier, `datetime_obj` will be a `datetime` with a valid `tzinfo`. Calling `datetime_obj.timetuple()` results in a local `struct_time`, which `time.mktime` converts to a local timestamp, which when eventually passed to `email.utlils.formatdate` will result in a value skewed by a margin equal to the local tz offset.

For example (my timezone is US/Central):
```python
>>> import datetime
>>> import time
>>> import email.utils
>>> from dateutil.tz import tzutc, tzlocal
>>> datetime.datetime(2015, 6, 17, 22, 11, 58, tzinfo=tzutc())
datetime.datetime(2015, 6, 17, 22, 11, 58, tzinfo=tzutc())
>>> time.mktime(_.timetuple())
1434600718.0
>>> email.utils.formatdate(_, usegmt=True)
'Thu, 18 Jun 2015 04:11:58 GMT'
```

I noticed this problem when trying to use (in boto3) `s3.Object`'s `last_modified` attribute to determine if an object had changed since it was last retrieved like this: `s3.Object.get(InModifiedSince=o.last_modified.isoformat())`

[HIDDEN]
[HIDDEN]

[HIDDEN] allows `value` to be a `datetime` in addition to the already supported `integer` and `string` types (would make boto3 docs correct in places where datetime is given as a parameter type).

Calling [HIDDEN] But, I think it expresses the expectation more clearly.

[HIDDEN] produces a UTC timestamp that `_timestamp_rfc822` will convert to a string representing the same moment in time that `datetime_obj` represented.

For example:
```python
>>> import datetime
>>> import calendar
>>> import email.utils
>>> from dateutil.tz import tzutc, tzlocal
>>> datetime.datetime(2015, 6, 17, 22, 11, 58, tzinfo=tzutc())
datetime.datetime(2015, 6, 17, 22, 11, 58, tzinfo=tzutc())
>>> calendar.timegm(_.utctimetuple())
1434579118
>>> email.utils.formatdate(_, usegmt=True)
'Wed, 17 Jun 2015 22:11:58 GMT'
```

### Additional contract requirements

- For timestamp header values supplied as timezone-bearing ISO8601 or RFC822 strings, serialize an RFC822 GMT value representing the same instant, without skew caused by the machine's local timezone.
- Accept `datetime` objects as timestamp header values, in addition to integer and string values.
