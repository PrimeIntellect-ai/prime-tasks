Forward references
Hello, there's some food for thought. Imagine a class referencing itself.

```
@attr.s
class A:
    a: 'A' = attr.ib()
```

This is the proper way of doing this as per mypy. In the case of attrs though:

```
>>> attr.fields(A).a
Attribute(name='a', default=NOTHING, validator=None, repr=True, cmp=True, hash=None, init=True, convert=None, metadata=mappingproxy({}), type='A')
```

The string just gets copied into the type attribute. `A.__annotations__` has the same problem. Ideally the type would be the actual class object. Mypy deals with this by having more than one pass when parsing.

The first question to answer if whether we should deal with this here, in attrs, or let code making use of the type attribute deal with it. Maybe instead of expecting higher levels to deal with this, Python itself should handle it (although good luck waiting for this :). I think it's worth trying to deal with this problem in attrs, to make it easier for others.

Dealing with just a class referencing itself is very doable. Now imagine circular references.

```
@attr.s
class A:
    b: 'B' = attr.ib()

@attr.s
class B:
    a: A = attr.ib()
```

Not really sure what to do here.

### Additional contract requirements

Add a public function `resolve_types(cls, globalns=None, localns=None)` in the `attr` module, exposed as `attr.resolve_types`.

It resolves string-based and forward-reference type annotations on an `attrs` class, updating the corresponding `Attribute.type` values in place to the resolved types, and returns the same class `cls` so that it can also be used as a class decorator.

`globalns` and `localns` are optional dictionaries of names used to resolve forward references. A forward-reference name that is available only in the supplied `globalns` must be resolved from there.
