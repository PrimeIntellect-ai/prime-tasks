Support for RFC 3339 in target time zone
I'm not able to get times to print in RFC 3339 using the `format_datetime` function:

```
>>> get_local_timezone()

  get_local_timezone()

    = America/Los_Angeles    [String]

>>> format_datetime("%Y-%m-%dT%H:%M:%S%:z", local(now()))

  format_datetime("%Y-%m-%dT%H:%M:%S%:z", local(now()))

    = 2024-02-23T22:01:52+00:00    [String]

>>> now()

  now()

    = Fri, 23 Feb 2024 14:01:54 -0800    [DateTime]
```

According to [the chrono docs](https://docs.rs/chrono/latest/chrono/format/strftime/index.html#specifiers), `%z` and friends should give the _local offset_ relative to UTC. However, it looks like the TZ info is getting dropped before being sent to the formatter and it's always displaying in UTC. (I would also like to add formatters/parsers for the reference format to the prelude, but I'm not sure if others would find that useful.)
