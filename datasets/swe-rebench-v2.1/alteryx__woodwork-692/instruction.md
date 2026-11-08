Add avoid_index parameter to mutual info to allow for more control
- We should add the following parameters to the mutual info function and associated defaults.
    -  `avoid_index=False`
- This way the end-user can have more control of the logic for calculating MI
- This is for the current DataTable implementation

### Additional contract requirements

The mutual-information parameter controlling whether the designated index column is analyzed is named `include_index` and defaults to `False`. When `False`, the designated index column is omitted from mutual-information calculations; when `True`, it is included only if its logical type is supported. The `avoid_index` spelling in the base text is superseded and is not a parameter that callers must provide.
