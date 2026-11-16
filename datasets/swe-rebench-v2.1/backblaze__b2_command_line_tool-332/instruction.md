CLI Sync errors
Hi all,
after i finished my first sync to Cloud after 3 weeks, i have now errors while syncing new files to the Cloud.

The following lines occurs after a few seconds when i start my CLI Command
```
C:\Program Files\Python36\Scripts>b2.exe sync --excludeRegex DfsrPrivate --threads 10 --keepDays 30 --replaceNewer \\?\D:\DFS\Daten b2://Nuernberg01/Daten

ERROR:b2.console_tool:ConsoleTool unexpected exception
Traceback (most recent call last):
  File "c:\program files\python36\lib\site-packages\b2\console_tool.py", line 992, in run_command
    return command.run(args)
  File "c:\program files\python36\lib\site-packages\b2\console_tool.py", line 781, in run
    dry_run=args.dryRun,
  File "c:\program files\python36\lib\site-packages\logfury\v0_1\trace_call.py", line 84, in wrapper
    return function(*wrapee_args, **wrapee_kwargs)
  File "c:\program files\python36\lib\site-packages\b2\sync\sync.py", line 251, in sync_folders
    source_folder, dest_folder, args, now_millis, reporter
  File "c:\program files\python36\lib\site-packages\b2\sync\sync.py", line 150, in make_folder_sync_actions
    sync_type, source_file, dest_file, source_folder, dest_folder, args, now_millis
  File "c:\program files\python36\lib\site-packages\b2\sync\sync.py", line 106, in make_file_sync_actions
    for action in policy.get_all_actions():
  File "c:\program files\python36\lib\site-packages\b2\sync\policy.py", line 104, in get_all_actions
    for action in self._get_hide_delete_actions():
  File "c:\program files\python36\lib\site-packages\b2\sync\policy.py", line 177, in _get_hide_delete_actions
    self._keepDays, self._now_millis
  File "c:\program files\python36\lib\site-packages\b2\sync\policy.py", line 254, in make_b2_keep_days_actions
    assert prev_age_days is None or prev_age_days <= age_days
AssertionError
Traceback (most recent call last):
  File "C:\Program Files\Python36\Scripts\b2-script.py", line 11, in <module>
    load_entry_point('b2==0.7.0', 'console_scripts', 'b2')()
  File "c:\program files\python36\lib\site-packages\b2\console_tool.py", line 1104, in main
    exit_status = ct.run_command(decoded_argv)
  File "c:\program files\python36\lib\site-packages\b2\console_tool.py", line 992, in run_command
    return command.run(args)
  File "c:\program files\python36\lib\site-packages\b2\console_tool.py", line 781, in run
    dry_run=args.dryRun,
  File "c:\program files\python36\lib\site-packages\logfury\v0_1\trace_call.py", line 84, in wrapper
    return function(*wrapee_args, **wrapee_kwargs)
  File "c:\program files\python36\lib\site-packages\b2\sync\sync.py", line 251, in sync_folders
    source_folder, dest_folder, args, now_millis, reporter
  File "c:\program files\python36\lib\site-packages\b2\sync\sync.py", line 150, in make_folder_sync_actions
    sync_type, source_file, dest_file, source_folder, dest_folder, args, now_millis
  File "c:\program files\python36\lib\site-packages\b2\sync\sync.py", line 106, in make_file_sync_actions
    for action in policy.get_all_actions():
  File "c:\program files\python36\lib\site-packages\b2\sync\policy.py", line 104, in get_all_actions
    for action in self._get_hide_delete_actions():
  File "c:\program files\python36\lib\site-packages\b2\sync\policy.py", line 177, in _get_hide_delete_actions
    self._keepDays, self._now_millis
  File "c:\program files\python36\lib\site-packages\b2\sync\policy.py", line 254, in make_b2_keep_days_actions
    assert prev_age_days is None or prev_age_days <= age_days
AssertionError
```
I have no Idea what to do?

### Additional contract requirements

- When a source file exists and the destination versions are uploads with IDs 1, 2, and 3 and relative dates -5, -10, and -3 days respectively, with `keep_days=7`, the keep-days actions must be exactly `['b2_delete(folder/a, 3, (old version))']`.
