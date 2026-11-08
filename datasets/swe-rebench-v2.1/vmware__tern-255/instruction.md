Add download_url property to Package class
**Description**
SPDX documents require a mandatory `Package Download Location` as described in PR #182.
Add `download_url` as a property to the `Package` class.
Add a test for the property.

**Implementation**
In `tern/classes/package.py`:
```
[HIDDEN]
```
In `tests/test_class_package.py`, add a `download_url` assert test for `TestInstance`, `TestSetters` and `TestGetters`.

**References**
See other properties in `tern/classes/package.py` and tests for these properties in `tests/test_class_package.py`

**Super Issues**
#239

### Additional contract requirements

- A newly constructed `Package` has an empty-string `download_url` value.
- `download_url` is readable and writable; after assigning a value, reading the property returns that value.
