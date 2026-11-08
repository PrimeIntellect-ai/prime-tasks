Unique profile
* Faker version: 17.4.0
* OS: Archlinux

Data unicity and profile are two great faker features, bun unfortunately they don't fit well together:

```python
>>> import faker
>>> fake = faker.Faker()
>>> fake.unique.profile()
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File ".../site-packages/faker/proxy.py", line 314, in wrapper
    if retval not in generated:
TypeError: unhashable type: 'dict'
```

I suggest implementing unique profile generation, where each value in the profile would be unique.

### Additional contract requirements

- `fake.unique.profile()` must not raise `TypeError` for the unhashable
  `dict` returned by the profile provider; it must return the generated
  profile.
- Successive calls to `fake.unique.profile()` on the same `Faker` instance
  must return distinct profiles: the uniqueness check applies to the whole
  returned profile, so no two profiles returned through the `.unique` portal
  are equal.
