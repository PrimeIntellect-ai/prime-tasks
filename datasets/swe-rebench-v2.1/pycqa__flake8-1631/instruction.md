flake8 does not start after upgrade from 4.0.1 to 5.0.0
### how did you install flake8?

```console
pip install flake8
```


### unmodified output of `flake8 --bug-report`

```json
{
"error": "impossible to provide this, --bug-report exits with an Exception"
}
```


### describe the problem

#### what I expected to happen

flake8 runs, it stopped working after our CI automatically upgraded from 4.0.1 to 5.0.0. Running on Python 3.8 which is installed through RHELs Software Collections.

#### commands ran

```console
$ flake8 .
Traceback (most recent call last):
  File "/home/x/repo/.env/bin/flake8", line 8, in <module>
    sys.exit(main())
  File "/home/x/repo/.env/lib64/python3.8/site-packages/flake8/main/cli.py", line 22, in main
    app.run(argv)
  File "/home/x/repo/.env/lib64/python3.8/site-packages/flake8/main/application.py", line 336, in run
    self._run(argv)
  File "/home/x/repo/.env/lib64/python3.8/site-packages/flake8/main/application.py", line 324, in _run
    self.initialize(argv)
  File "/home/x/repo/.env/lib64/python3.8/site-packages/flake8/main/application.py", line 308, in initialize
    self.register_plugin_options()
  File "/home/x/repo/.env/lib64/python3.8/site-packages/flake8/main/application.py", line 140, in register_plugin_options
    self.option_manager.register_plugins(self.plugins)
  File "/home/x/repo/.env/lib64/python3.8/site-packages/flake8/options/manager.py", line 376, in register_plugins
    add_options(self)
  File "/home/x/repo/.env/lib64/python3.8/site-packages/mccabe.py", line 256, in add_options
    parser.add_option(flag, **kwargs)
  File "/home/x/repo/.env/lib64/python3.8/site-packages/flake8/options/manager.py", line 398, in add_option
    self._current_group.add_argument(*option_args, **option_kwargs)
  File "/opt/rh/rh-python38/root/usr/lib64/python3.8/argparse.py", line 1386, in add_argument
    return self._add_action(action)
  File "/opt/rh/rh-python38/root/usr/lib64/python3.8/argparse.py", line 1590, in _add_action
    action = super(_ArgumentGroup, self)._add_action(action)
  File "/opt/rh/rh-python38/root/usr/lib64/python3.8/argparse.py", line 1400, in _add_action
    self._check_conflict(action)
  File "/opt/rh/rh-python38/root/usr/lib64/python3.8/argparse.py", line 1539, in _check_conflict
    conflict_handler(action, confl_optionals)
  File "/opt/rh/rh-python38/root/usr/lib64/python3.8/argparse.py", line 1548, in _handle_conflict_error
    raise ArgumentError(action, message % conflict_string)
argparse.ArgumentError: argument --max-complexity: conflicting option string: --max-complexity
```
