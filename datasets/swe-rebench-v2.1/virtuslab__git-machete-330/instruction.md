`AttributeError: 'str' object has no attribute 'full_name'` due to (?) mistyped `CommandLineOptions.opt_branch`
For an already existing, but not yet managed branch `foo/bar`:

```
$ git machete add foo/bar
Traceback (most recent call last):
  File "/usr/local/bin/git-machete", line 4, in <module>
    __import__('pkg_resources').run_script('git-machete==3.5.0', 'git-machete')
  File "/usr/lib/python3.7/site-packages/pkg_resources/__init__.py", line 666, in run_script
    self.require(requires)[0].run_script(script_name, ns)
  File "/usr/lib/python3.7/site-packages/pkg_resources/__init__.py", line 1469, in run_script
    exec(script_code, namespace, namespace)
  File "/usr/local/lib/python3.7/site-packages/git_machete-3.5.0-py3.7.egg/EGG-INFO/scripts/git-machete", line 19, in <module>
  File "/usr/local/lib/python3.7/site-packages/git_machete-3.5.0-py3.7.egg/git_machete/cli.py", line 803, in main
  File "/usr/local/lib/python3.7/site-packages/git_machete-3.5.0-py3.7.egg/git_machete/cli.py", line 522, in launch
  File "/usr/local/lib/python3.7/site-packages/git_machete-3.5.0-py3.7.egg/git_machete/client.py", line 263, in add
  File "/usr/local/lib/python3.7/site-packages/git_machete-3.5.0-py3.7.egg/git_machete/client.py", line 1502, in __infer_upstream
  File "/usr/local/lib/python3.7/site-packages/git_machete-3.5.0-py3.7.egg/git_machete/client.py", line 1479, in __match_log_to_filtered_reflogs
  File "/usr/local/lib/python3.7/site-packages/git_machete-3.5.0-py3.7.egg/git_machete/git_operations.py", line 495, in spoonfeed_log_shas
  File "/usr/local/lib/python3.7/site-packages/git_machete-3.5.0-py3.7.egg/git_machete/git_operations.py", line 487, in __get_log_shas
AttributeError: 'str' object has no attribute 'full_name'
```

This is most likely due to [HIDDEN]... not sure why it passed mypy in the first place, pls investigate.

Also, regression test + preferable a systematic solution against this kind of errors would be very useful.

### Additional contract requirements

Slash-containing local branch names must be accepted by `git machete add <branch>`, `git machete add --onto=<branch>`, and each entry in the comma-separated `git machete discover --roots=<branch>[,<branch>...]` option.
