[Bug]: External Resources "get_object_resources" method fails
### What happened?

Returns a Value Error regarding the shape of the input for the pandas DataFrame being generated.

### Steps to Reproduce

```shell
nwbfile = ERNWBFile(
    session_description='session_description',
    identifier='identifier',
    session_start_time=datetime.datetime.now(datetime.timezone.utc),
    experimenter=["Dichter, Benjamin K.", "Smith, Alex"],
)


nwbfile.external_resources.add_ref(
    container=nwbfile,
    attribute="experimenter",
    key="Dichter, Benjamin K.",
    resource_name="ORCID",
    resource_uri="https://orcid.org/",
    entity_id="0000-0001-5725-6910",
    entity_uri="https://orcid.org/0000-0001-5725-6910",
)

path = 'test_ext_resources5.nwb'
with NWBHDF5IO(path, mode='w') as io:
    io.write(nwbfile)

io = NWBHDF5IO(path, mode='r', load_namespaces=True)
read_nwbfile = io.read()
read_nwbfile.external_resources.get_object_resources(container=read_nwbfile, relative_path='ERNWBFile/general/experimenter')
```


### Traceback

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Input In [33], in <cell line: 2>()
      1 import pandas as pd
----> 2 [HIDDEN]

File ~/opt/anaconda3/envs/hdmf_clone/lib/python3.9/site-packages/pandas/core/frame.py:711, in DataFrame.__init__(self, data, index, columns, dtype, copy)
    702         mgr = arrays_to_mgr(
    703             arrays,
    704             columns,
   (...)
    708             typ=manager,
    709         )
    710     else:
--> 711         mgr = ndarray_to_mgr(
    712             data,
    713             index,
    714             columns,
    715             dtype=dtype,
    716             copy=copy,
    717             typ=manager,
    718         )
    719 else:
    720     mgr = dict_to_mgr(
    721         {},
    722         index,
   (...)
    725         typ=manager,
    726     )

File ~/opt/anaconda3/envs/hdmf_clone/lib/python3.9/site-packages/pandas/core/internals/construction.py:322, in ndarray_to_mgr(values, index, columns, dtype, copy, typ)
    317 # _prep_ndarray ensures that values.ndim == 2 at this point
    318 index, columns = _get_axes(
    319     values.shape[0], values.shape[1], index=index, columns=columns
    320 )
--> 322 _check_values_indices_shape_match(values, index, columns)
    324 if typ == "array":
    326     if issubclass(values.dtype.type, str):

File ~/opt/anaconda3/envs/hdmf_clone/lib/python3.9/site-packages/pandas/core/internals/construction.py:391, in _check_values_indices_shape_match(values, index, columns)
    389 passed = values.shape
    390 implied = (len(index), len(columns))
--> 391 raise ValueError(f"Shape of passed values is {passed}, indices imply {implied}")

ValueError: Shape of passed values is (1, 1), indices imply (1, 4)
```


### Operating System

macOS

### Python Executable

Python

### Python Version

3.7

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/hdmf-dev/hdmf/blob/dev/.github/CODE_OF_CONDUCT.md)
- [X] Have you checked the [Contributing](https://github.com/hdmf-dev/hdmf/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/hdmf-dev/hdmf/issues)?

### Additional contract requirements

After an external-resource reference has been registered for an object's key, `get_object_resources` must return the associated resource/entity row or rows for that object after the external-resources data has been written and read back. A write/read round trip must not cause the lookup to fail because the stored data has a different representation.

For an object field associated with multiple registered keys, `get_object_resources` returns a row for each associated resource/entity entry across those keys, rather than only one row for the object.
