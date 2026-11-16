--excludeDirRegex does not work when source is B2
The new filtering that lets you exclude an entire directory works in the `LocalFolder` class, but not the `B2Folder` class.

I think there are two possible approaches to fixing it: (1) change B2Folder to simulate the existence of directories, and check them for exclusion, or (2) extend `ScanPoliciesManager.should_exclude_file` to also test whether any of the directories in the path are excluded.  I like #2, but I think it would need optimization to avoid checking every parent directory of every file.

### Additional contract requirements

- `ScanPoliciesManager` lives in `b2/sync/scan_policies.py` and is constructed as `ScanPoliciesManager(include_file_regexes=tuple(), exclude_file_regexes=tuple(), exclude_dir_regexes=tuple())`, where each argument is an iterable of regular-expression strings. `exclude_dir_regexes` holds the patterns for directories to exclude.
- `ScanPoliciesManager.should_exclude_directory(dir_path)` returns `True` when `dir_path` matches any pattern in `exclude_dir_regexes`, and `False` otherwise.
- `ScanPoliciesManager.should_exclude_file(file_path)` returns `True` when the file should be omitted from a scan, including when any directory component of `file_path` matches a pattern in `exclude_dir_regexes`.
- `B2Folder.all_files(reporter, policies_manager)` in `b2/sync/folder.py` applies the supplied `policies_manager` while enumerating files, so files excluded by the policy are not returned.
