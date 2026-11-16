should pybids more lenient or at least get a dedicated exception like NonCompliantBIDSError
ATM pybids immediately throws a generic ValueError if found contained derivatives dataset is not fully compliant:

```shell
/tmp > datalad install https://github.com/OpenNeuroDatasets/ds001868 && cd ds001868
[INFO   ] Cloning https://github.com/OpenNeuroDatasets/ds001868 [1 other candidates] into '/tmp/ds001868'
[INFO   ]   Remote origin not usable by git-annex; setting annex-ignore
[INFO   ] access to 1 dataset sibling s3-PRIVATE not auto-enabled, enable with:
| 		datalad siblings -d "/tmp/ds001868" enable -s s3-PRIVATE
install(ok): /tmp/ds001868 (dataset)

/tmp/ds001868 > python -c 'from bids import BIDSLayout; b=BIDSLayout(".", derivatives=True)'
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/home/yoh/proj/bids/pybids/bids/layout/layout.py", line 227, in __init__
    index_metadata=index_metadata)
  File "/home/yoh/proj/bids/pybids/bids/layout/layout.py", line 555, in add_derivatives
    raise ValueError("Every valid BIDS-derivatives dataset must "
ValueError: Every valid BIDS-derivatives dataset must have a PipelineDescription.Name field set inside dataset_description.json.
```
But I wonder
- if this should be a warning and not error (optionally or not)
- there should be a dedicated exception (e.g. `NonCompliantBIDSError(ValueError)` and `NonCompliantDerivativesBIDSError(NonCompliantBIDSError)`) which would be thrown here instead of a generic ValueError which makes it fragile to handle such cases programmatically

### Additional contract requirements

- The public module `bids.exceptions` defines `BIDSValidationError` and `BIDSDerivativesValidationError` for validation failures. A derivatives validation exception is also a BIDS validation exception.
- `BIDSLayout.add_derivatives(...)` raises `BIDSDerivativesValidationError` when a derivatives dataset is missing `PipelineDescription.Name`, or when a pipeline name has already been added.
- When constructing a layout, dataset validation failures are reported as `BIDSValidationError`.
