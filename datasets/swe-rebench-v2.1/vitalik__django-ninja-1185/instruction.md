[BUG] `SmallAutoField` missing from `ninja.orm.fields`
**Describe the bug**
`SmallAutoField` missing from `ninja.orm.fields`
If you try to use `create_schema` on a model that has a `SmallAutoField`, you will get:
```
File "/usr/local/lib/python3.12/site-packages/ninja/orm/fields.py", line 144, in get_schema_field
    python_type = TYPES[internal_type]
                  ~~~~~^^^^^^^^^^^^^
```

**Versions (please complete the following information):**
python 3.12
django 5.0.4
ninja 1.1.0
pydantic 2.6.4
