NoneTrait and Union use a different metadata name for static default
On Traits 6.0, `Either` is the only trait type where static default is defined via the metadata named `"default"`, all other trait types have their static default provided via the metadata named `"default_value"`, which is the name assumed by the base `TraitType`.

On master, `NoneTrait` and `Union` expect the static default to be provided via the `"default"` metadata, while it is consistent with `Either`, it is inconsistent with the base class and other trait types.

If one tries to define `Union` with `default_value` as the metadata, an error occurs:
```
>>> Union(Str(), List(), default_value="123")

~/Work/ETS/traits/traits/trait_types.py in __init__(self, *traits, **metadata)
   3864
   3865         self.default_value_type = _infer_default_value_type(default_value)
-> 3866         super().__init__(default_value, **metadata)
   3867
   3868     def validate(self, obj, name, value):

TypeError: __init__() got multiple values for argument 'default_value'
```

Since these two trait types have not been released yet, we can still fix these.

### Additional contract requirements

- `Union` takes its static default from the `default_value` metadata, consistent with other trait types. For example, `Union(Int(), Str(), default_value="abc")` gives instances the default `"abc"`.
- Passing a metadata named `default` to `Union` raises a `ValueError`, so that code migrating from `Either` is told to use `default_value` instead.
- `NoneTrait` takes its static default from the `default_value` metadata. Only `None` is accepted there: a non-`None` `default_value` raises a `ValueError`.
