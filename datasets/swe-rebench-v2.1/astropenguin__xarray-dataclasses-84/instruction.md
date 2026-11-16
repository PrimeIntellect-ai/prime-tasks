Fix parsing dataclass under __future__.annotations enabled
The current (v0.4.0) dataclass parser (`xarray_dataclasses.parse`) does not work when the postponed evaluation of annotations ([PEP 563](https://www.python.org/dev/peps/pep-0563)) is enabled by importing `from __future__ import annotations`. This is because the parser gets type hints of dataclass fields from `cls.__dataclass_fields__`: Under such environments, `field.type` becomes string and loses runtime information.

This issue is for resolving the problem by using [HIDDEN] that ensures evaluated type hints made from strings.

### Additional contract requirements

- When postponed annotations are enabled, `xarray_dataclasses.parse` must interpret dataclass field annotations and retain the type metadata needed to parse them, rather than treating their string representations as the field types.
