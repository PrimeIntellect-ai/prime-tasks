Incorrect ValueError: AllowedPattern can only be used with parameters of the String type
Example:

```python
    cft.add_parameter(
        Parameter(
            "Foo",
            Type="CommaDelimitedList",
            AllowedPattern="^[A-Z]{2}$",
            Default="",
        )
    )
```

According to the [AWS docs](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html) this should be allowed:
> AllowedPattern
> A regular expression that represents the patterns to allow for String or CommaDelimitedList types. When applied on a parameter of type String, the pattern must match the entire parameter value provided. When applied to a parameter of type CommaDelimitedList, the pattern must match each value in the list.

### Additional contract requirements

- `Parameter.validate()` returns `None` when the parameter configuration is valid.
- The validation must accept `AllowedPattern` for parameters of type `String` and `CommaDelimitedList`.
- `AllowedPattern` is rejected for parameters of type `Number`: `validate()` raises `ValueError` and the message contains the offending property name `AllowedPattern`.
- The numeric limit properties `MaxValue` and `MinValue` are rejected for parameters of type `String` and `CommaDelimitedList`: `validate()` raises `ValueError` and the message contains the offending property name.
