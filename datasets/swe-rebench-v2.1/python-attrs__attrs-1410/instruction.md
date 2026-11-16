unhelpful message "ValueError: Type annotation and type argument cannot both be present"
Getting this message because I both have the type annotation and type defined on a custom attribute class which is reasonable considering the ambiguity.

However I think the message itself could be more helpful by displaying the name of the attribute to eliminate the variable hunt.

My suggested change is:

https://github.com/python-attrs/attrs/blob/2afd663bf40e4a8209986accdfb1e2d53afc15e2/src/attr/_make.py#L2354
```python
    [HIDDEN]
                [HIDDEN]
            )
        inst_dict = {
            k: getattr(ca, k)
            for k
            in Attribute.__slots__
            if k not in (
                "name", "validator", "default", "type", "convert",
            )  # exclude methods and deprecated alias
        }
        return cls(
            name=name, validator=ca._validator, default=ca._default, type=type,
            **inst_dict
        )
 ```

### Additional contract requirements

- When an attribute has both a type annotation and an explicit type argument, the resulting `ValueError` message must identify the attribute by name.
