Inconsistent (and broken) behavior for Optional Metadata values
Currently the `Metadata` class is inconsistent and in some cases broken in how it handles optional metadata values that don't currently have a value.

I added a quick test to the test suite that looks like:

```python
    @pytest.mark.parametrize(
        "field_name",
        sorted(metadata._RAW_TO_EMAIL_MAPPING.keys() - metadata._REQUIRED_ATTRS),
    )
    def test_can_access_omitted_optional_value(self, field_name):
        # Create a minimal metadata that has only the required fields.
        meta = metadata.Metadata.from_raw(
            {
                "metadata_version": metadata._VALID_METADATA_VERSIONS[-1],
                "name": "foo",
                "version": "1.0",
            }
        )

        # Accessing any optional field should be fine, and should return the
        # "zero" value for that field.
        value = getattr(meta, field_name)
        if isinstance(value, str):
            assert value == ""
        elif isinstance(value, list):
            assert value == []
        elif isinstance(value, dict):
            assert value == {}
        else:
            assert False, "unknown type"
```

And I ended up with 3 errors:

```
======================================================= FAILURES =======================================================
____________________ TestMetadata.test_can_access_omitted_optional_value[description_content_type] _____________________

self = <tests.test_metadata.TestMetadata object at 0x7f2fd1242090>, field_name = 'description_content_type'

    @pytest.mark.parametrize(
        "field_name",
        sorted(metadata._RAW_TO_EMAIL_MAPPING.keys() - metadata._REQUIRED_ATTRS),
    )
    def test_can_access_omitted_optional_value(self, field_name):
        # Create a minimal metadata that has only the required fields.
        meta = metadata.Metadata.from_raw(
            {
                "metadata_version": metadata._VALID_METADATA_VERSIONS[-1],
                "name": "foo",
                "version": "1.0",
            }
        )

        # Accessing any optional field should be fine, and should return the
        # "zero" value for that field.
>       value = getattr(meta, field_name)

tests/test_metadata.py:648:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
.nox/tests-3-11/lib/python3.11/site-packages/packaging/metadata.py:525: in __get__
    value = converter(value)
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <packaging.metadata._Validator object at 0x7f2fd110b610>, value = ''

    def _process_description_content_type(self, value: str) -> str:
        content_types = {"text/plain", "text/x-rst", "text/markdown"}
        message = email.message.EmailMessage()
        message["content-type"] = value

        content_type, parameters = (
            # Defaults to `text/plain` if parsing failed.
            message.get_content_type().lower(),
            message["content-type"].params,
        )
        # Check if content-type is valid or defaulted to `text/plain` and thus was
        # not parseable.
        if content_type not in content_types or content_type not in value.lower():
>           raise self._invalid_metadata(
                f"{{field}} must be one of {list(content_types)}, not {value!r}"
            )
E           packaging.metadata.InvalidMetadata: 'description-content-type' must be one of ['text/x-rst', 'text/plain', 'text/markdown'], not ''

.nox/tests-3-11/lib/python3.11/site-packages/packaging/metadata.py:592: InvalidMetadata
____________________________ TestMetadata.test_can_access_omitted_optional_value[keywords] _____________________________

self = <packaging.metadata._Validator object at 0x7f2fd110b490>
instance = <packaging.metadata.Metadata object at 0x7f2fcc778d90>, _owner = <class 'packaging.metadata.Metadata'>

    def __get__(self, instance: "Metadata", _owner: Type["Metadata"]) -> T:
        # With Python 3.8, the caching can be replaced with functools.cached_property().
        # No need to check the cache as attribute lookup will resolve into the
        # instance's __dict__ before __get__ is called.
        cache = instance.__dict__
        try:
>           value = instance._raw[self.name]  # type: ignore[literal-required]
E           KeyError: 'keywords'

.nox/tests-3-11/lib/python3.11/site-packages/packaging/metadata.py:509: KeyError

During handling of the above exception, another exception occurred:

self = <tests.test_metadata.TestMetadata object at 0x7f2fd1243110>, field_name = 'keywords'

    @pytest.mark.parametrize(
        "field_name",
        sorted(metadata._RAW_TO_EMAIL_MAPPING.keys() - metadata._REQUIRED_ATTRS),
    )
    def test_can_access_omitted_optional_value(self, field_name):
        # Create a minimal metadata that has only the required fields.
        meta = metadata.Metadata.from_raw(
            {
                "metadata_version": metadata._VALID_METADATA_VERSIONS[-1],
                "name": "foo",
                "version": "1.0",
            }
        )

        # Accessing any optional field should be fine, and should return the
        # "zero" value for that field.
>       value = getattr(meta, field_name)

tests/test_metadata.py:648:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <packaging.metadata._Validator object at 0x7f2fd110b490>
instance = <packaging.metadata.Metadata object at 0x7f2fcc778d90>, _owner = <class 'packaging.metadata.Metadata'>

    def __get__(self, instance: "Metadata", _owner: Type["Metadata"]) -> T:
        # With Python 3.8, the caching can be replaced with functools.cached_property().
        # No need to check the cache as attribute lookup will resolve into the
        # instance's __dict__ before __get__ is called.
        cache = instance.__dict__
        try:
            value = instance._raw[self.name]  # type: ignore[literal-required]
        except KeyError:
            if self.name in _STRING_FIELDS:
                value = ""
            elif self.name in _LIST_FIELDS:
                value = []
            elif self.name in _DICT_FIELDS:
                value = {}
            else:  # pragma: no cover
>               assert False
E               AssertionError

.nox/tests-3-11/lib/python3.11/site-packages/packaging/metadata.py:518: AssertionError
_________________________ TestMetadata.test_can_access_omitted_optional_value[requires_python] _________________________

self = <tests.test_metadata.TestMetadata object at 0x7f2fd1229790>, field_name = 'requires_python'

    @pytest.mark.parametrize(
        "field_name",
        sorted(metadata._RAW_TO_EMAIL_MAPPING.keys() - metadata._REQUIRED_ATTRS),
    )
    def test_can_access_omitted_optional_value(self, field_name):
        # Create a minimal metadata that has only the required fields.
        meta = metadata.Metadata.from_raw(
            {
                "metadata_version": metadata._VALID_METADATA_VERSIONS[-1],
                "name": "foo",
                "version": "1.0",
            }
        )

        # Accessing any optional field should be fine, and should return the
        # "zero" value for that field.
        value = getattr(meta, field_name)
        if isinstance(value, str):
            assert value == ""
        elif isinstance(value, list):
            assert value == []
        elif isinstance(value, dict):
            assert value == {}
        else:
>           assert False, "unknown type"
E           AssertionError: unknown type
E           assert False

tests/test_metadata.py:656: AssertionError
```


Of those 3 errors, the `description_content_type` and `keywords` both just appear to be the same basic problem, the Metadata validators don't always correctly handle running when the value doesn't exist. That's just a bug that should be fixed (which I'm happy to make a PR to fix them).

The `requires_python` one though raises an interesting question, in what is the correct value for an optional field that doesn't have a value? It appears that currently what (most) of the validators do is return the "zero" value for their respective type (`""` for `str`, `[]` for `list`, etc).

A zero value is probably fine for primitive types (although going into the future, if we get metadata formats that can express the difference between empty and not present it could limit our ability to express that), but for non primitive types trying to create a zero value feels like fundamentally the wrong thing to do. Currently the only non primitive, optional metadata field is `Metadata.requires_python`.

I think a better behavior here is that each optional attribute has their type unioned with `None`, and we use `None` to express "an optional value which was not provided". That is a pretty common pattern in Python, and it is one we can easily consistently apply no matter whether the type is a primitive or non-primitive type.
