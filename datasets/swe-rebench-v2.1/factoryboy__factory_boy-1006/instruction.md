The unreleased `Transformer` has a conflicting API with the overall design
#### Description
For most declarations, I can override the default mechanism by passing an explicit value:

```python
>>> UserFactory().email
"john.doe@example.org"
>>> UserFactory(email="jane.doe@example.org").email
"jane.doe@example.org"
```

If the factory uses a `factory.Transformer` field, I can't force a value:

```python
>>> UserFactory().password
"pbkdf2_sha256$216000$Gj2b9f0Ln1ms$1dBlLEYrtGiwEA219JU831VAdscD2f9nFY37PrNfCDU="
>>> UserFactory(
...     password="pbkdf2_sha256$216000$Gj2b9f0Ln1ms$1dBlLEYrtGiwEA219JU831VAdscD2f9nFY37PrNfCDU="
... ).password
"pbkdf2_sha256$216000$EUKlFdNViyB5$vcfPaK6H7pDiQAa9ZIbFoj5oj55tUyHKHDUfxI4GIeY="
```

As a user, it is quite confusing to have very different behaviours for fields; if I have a specific password hash (in this example), I need to have a way to set it.

#### Next steps

I'm not sure we can officially release the `factory.Transformer` (and related code) without addressing this topic first; how can a user bypass the transform?

### Additional contract requirements

- A caller can supply a value for a `factory.Transformer` field that is used exactly as given, without applying the field's transform, by wrapping it in `factory.Transformer.Force(...)`. For example, `UserFactory(password=factory.Transformer.Force(hash_value)).password` returns `hash_value` unchanged.
- A plain value passed as an override is still transformed, and the field's default value is still transformed when no override is given.
