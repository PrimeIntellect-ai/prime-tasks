Keep the same "case" in the class names
At this moment it seems that xsData is transforming the casing of an element to something "pythonish" would it be possible to keep the "original" element casing as it matches the casing in the XML Schema and obviously the XML itself?

### Additional contract requirements

- Add a public function `original_case(value: str, **kwargs: Any) -> str` in module `xsdata.utils.text` that returns `value` unchanged and accepts arbitrary extra keyword arguments.
- The `originalCase` naming convention, exposed as `NameCase.ORIGINAL` in module `xsdata.models.config`, preserves the input string unchanged, including when it is called with additional keyword arguments such as `class_name`.
