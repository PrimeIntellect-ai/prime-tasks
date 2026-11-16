[Adjust Rule] SIM909
## Desired change

* **Rule(s)**: SIM909
* **Adjustment**: Consider allowing declarations on classes

## Explanation

I have this code:

```python
database = Database(url=url)
metadata = sqlalchemy.MetaData()

class BaseMeta:
    metadata = metadata
    database = database
```

The `BaseMeta` class is used for database models as the `Meta` baseclass.

This is currently flagged by SIM909, but after reading through the rationale of the rule, I think this could be considered a false positive. Assignment of `metadata` to `metadata` on a class is not the same as outside a class right - it actually serves a purpose 🙂

What do you think?
