otioconvert to OTIOZ fails with relative media target_urls
## Description

otioconvert fails to convert OTIO to OTIOZ if there are media target_urls which start with "./"

Related bug: https://github.com/AcademySoftwareFoundation/OpenTimelineIO/issues/1783

## Reproduction Steps

1. Download the attached OTIO and media file.
2. Run this command:

```bash
% uvx --from opentimelineio otioconvert -i time_warp_test.otio -o time_warp_test.otioz
```

## Log output if appropriate

```
Traceback (most recent call last):
  File "/Users/jminor/.cache/uv/archive-v0/egUCtOWX8VKGzLpjlRQw-/bin/otioconvert", line 10, in <module>
    sys.exit(main())
  File "/Users/jminor/.cache/uv/archive-v0/egUCtOWX8VKGzLpjlRQw-/lib/python3.8/site-packages/opentimelineio/console/otioconvert.py", line 273, in main
    otio.adapters.write_to_file(
  File "/Users/jminor/.cache/uv/archive-v0/egUCtOWX8VKGzLpjlRQw-/lib/python3.8/site-packages/opentimelineio/adapters/__init__.py", line 203, in write_to_file
    return adapter.write_to_file(
  File "/Users/jminor/.cache/uv/archive-v0/egUCtOWX8VKGzLpjlRQw-/lib/python3.8/site-packages/opentimelineio/adapters/adapter.py", line 189, in write_to_file
    result = self._execute_function(
  File "/Users/jminor/.cache/uv/archive-v0/egUCtOWX8VKGzLpjlRQw-/lib/python3.8/site-packages/opentimelineio/plugins/python_plugin.py", line 144, in _execute_function
    return (getattr(self.module(), func_name)(**kwargs))
  File "/Users/jminor/.cache/uv/archive-v0/egUCtOWX8VKGzLpjlRQw-/lib/python3.8/site-packages/opentimelineio/adapters/otioz.py", line 93, in write_to_file
    result_otio, path_to_mr_map = utils._prepped_otio_for_bundle_and_manifest(
  [HIDDEN]
    [HIDDEN]
IndexError: tuple index out of range
```

## Sample data and other attachements

[otioconvert_relative_paths_to_otioz_bug_repro.zip](https://github.com/user-attachments/files/18043730/otioconvert_relative_paths_to_otioz_bug_repro.zip)

### Additional contract requirements

- Converting an OTIO to OTIOZ must succeed when media `target_url` values start with `./`.
- When the resulting OTIOZ is read back, each clip's media_reference.target_url must contain the source media file's basename.
