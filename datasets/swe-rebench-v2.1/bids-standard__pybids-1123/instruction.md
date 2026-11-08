MacOS Finder `._*` hidden metadata files cause pybids to crash
## Example
<details><summary><code>UnicodeDecodeError: 'utf-8' codec can't decode byte 0xb0 in position 37: invalid start byte</code> … <code>while trying to decode JSON from file […]/._sub-PA069_ses-V1W1_task-poke_run-2_bold.json</code></summary>

```Python
Traceback (most recent call last):
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/bids/layout/index.py", line 303, in load_json
    return json.load(handle)
  File "/opt/conda/envs/sdcflows/lib/python3.10/json/__init__.py", line 293, in load
    return loads(fp.read(),
  File "/opt/conda/envs/sdcflows/lib/python3.10/codecs.py", line 322, in decode
    (result, consumed) = self._buffer_decode(data, self.errors, final)
UnicodeDecodeError: 'utf-8' codec can't decode byte 0xb0 in position 37: invalid start byte

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/opt/conda/envs/sdcflows/bin/sdcflows", line 8, in <module>
    sys.exit(main())
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/sdcflows/cli/main.py", line 39, in main
    parse_args(argv)
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/sdcflows/cli/parser.py", line 281, in parse_args
    config.from_dict(vars(opts))
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/sdcflows/config.py", line 589, in from_dict
    execution.load(settings)
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/sdcflows/config.py", line 249, in load
    cls.init()
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/sdcflows/config.py", line 476, in init
    cls._layout = BIDSLayout(
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/bids/layout/layout.py", line 177, in __init__
    _indexer(self)
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/bids/layout/index.py", line 154, in __call__
    self._index_metadata()
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/bids/layout/index.py", line 415, in _index_metadata
    file_md.update(pl())
  File "/opt/conda/envs/sdcflows/lib/python3.10/site-packages/bids/layout/index.py", line 305, in load_json
    raise OSError(
OSError: Error occurred while trying to decode JSON from file /ocean/projects/med220004p/shared/data_raw/vannucci/bids_raw/sub-PA069/ses-V1W1/func/._sub-PA069_ses-V1W1_task-poke_run-2_bold.json
```

</details>

## Proposed Solution

I think [these types of files (`._*` and `.DS_Store`)](https://lists.apple.com/archives/applescript-users/2006/Jun/msg00180.html) can be safely ignored.

## Context

In analyzing someone else's read-only (to me) data, I hit this issue. I worked around it by creating a symlinked recreation of the data directory without the MacOS hidden metadata files, but I don't think that should have been necessary.

### Additional contract requirements

- macOS Finder metadata files — `._*` companion files and `.DS_Store` — must never be indexed, so that they cannot cause indexing to crash. This must hold even when a custom `ignore` list is supplied to `BIDSLayoutIndexer`: providing an explicit ignore list must not cause these metadata files to be indexed.
