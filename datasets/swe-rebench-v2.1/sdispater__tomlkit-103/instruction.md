Serializing OrderedDict (and dict in Python 3) does not preserve order
The following is the case in both Python 2.7 and Python 3.x.
```
>>> import tomlkit, json, collections
>>> json.dumps(collections.OrderedDict([('foo', 1), ('bar', 2), ('baz', 3)]))
'{"foo": 1, "bar": 2, "baz": 3}'
>>> tomlkit.dumps(collections.OrderedDict([('foo', 1), ('bar', 2), ('baz', 3)]))
'bar = 2\nbaz = 3\nfoo = 1\n'
```

### Additional contract requirements

When serializing an `OrderedDict`, preserve the insertion order of entries emitted within every TOML table, including nested tables.
