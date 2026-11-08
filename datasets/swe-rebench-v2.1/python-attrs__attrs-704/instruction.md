attr.asdict(retain_collection_types=False) doesn't support frozenset
Hey, I ran into some surprising behavior when using `attr.asdict()` with a frozen set.
I was expecting `retain_collection_types=False` to convert a frozenset to a list, as it does with a tuple or list, but it keeps it as a frozenset

Example
```py3
import attr

@attr.s
class Foo:
    bar = attr.ib()

DATA = (1, 2, 3)
print("set:", attr.asdict(Foo(set(DATA))))
print("frozenset", attr.asdict(Foo(frozenset(DATA))))
```

Output:
```sh
$ python attr_demo.py
set: {'bar': [1, 2, 3]}
frozenset {'bar': frozenset({1, 2, 3})}
```

Expected Output
```sh
$ python attr_demo.py
set: {'bar': [1, 2, 3]}
frozenset  {'bar': [1, 2, 3]}
```


it looks like the code change is [HIDDEN] on https://github.com/python-attrs/attrs/blob/master/src/attr/_funcs.py#L55
