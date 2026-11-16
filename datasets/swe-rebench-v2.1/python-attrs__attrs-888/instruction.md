`asdict` fails for attributes of type Mapping with keys of type `Tuple`
```
@attr.s
class A:
    a = attr.ib()

instance = A({(1, ): 1})
attr.asdict(instance)
```
produces:
`TypeError: unhashable type: 'list'`

when the `retain_collection_types` flag is set to false (the default).  This can take a while to figure out, since the error is not the most descriptive (and the classes are not toy examples like this one).
I just thought it would be worth mentioning. In any case, thanks for this awesome library.
