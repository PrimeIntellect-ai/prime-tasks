deprecate utils modules that are not intended for end-users
## Description of the problem
Most of our utils modules are not really intended to be used by end-users , but should be used via high-level interfaces that call these methods.

This follows an anti-pattern where there is high coupling between the `utils` module and other modules and reduced cohesion inside modules like `dataset`.

Also this crowds our online documentation with irrelevant functions no end-user will need.

## Description of a solution

Instead, we should increase the cohesion inside each module and reduce coupling between modules.

Candidates are:
- [x] `utils.aois` #1080
- [x] `utils.archives` -> `dataset._utils.archives` #1028
- [x] `utils.checks` -> `_utils._checks` #1094
- [x] remove `utils.decorators` #1008
- [x] `utils.downloads` -> `dataset._utils.downloads` #1030
- [x] `utils.filters` -> `events._utils._filters` #1032
- [x] `utils.parsing` -> `gaze._utils.parsing` #976
- [x] `utils.paths` -> `_utils._paths` #1029
- [ ] `utils.plotting` -> `plotting._utils.matlab` #1081
- [x] `utils.strings` -> `_utils._strings` #1031

### Additional contract requirements

- The path utilities `get_filepaths` and `match_filepaths` are provided by the module `pymovements._utils._paths`.
- `get_filepaths(path, extension=None, regex=None)` recursively returns a `list[pathlib.Path]` of the files found under `path`. `path` may be a `str` or a `pathlib.Path`. `extension` may be a single extension string (for example `'.txt'`) or a list of extension strings. `extension` and `regex` are mutually exclusive; passing both raises `ValueError`. When `path` is not a directory, an empty list is returned.
- `match_filepaths(path, regex, relative=True, relative_anchor=None)` recursively returns a `list[dict[str, str]]`, one dictionary per matching file, containing the named groups of `regex` plus a `'filepath'` key. When `relative` is `True`, `'filepath'` is relative to `relative_anchor` if one is given, otherwise relative to `path`. When `relative` is `False`, `'filepath'` is absolute. `path` must exist and be a directory, otherwise `ValueError` is raised.
- Calling `get_filepaths` or `match_filepaths` through the deprecated `pymovements.utils.paths` module emits a `DeprecationWarning`.
