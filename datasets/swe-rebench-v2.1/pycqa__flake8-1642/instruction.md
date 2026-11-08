Exception if HOME is not an existing path
### how did you install flake8?

```console
$ pip install flake8
```


### unmodified output of `flake8 --bug-report`

```json
{
  "platform": {
    "python_implementation": "CPython",
    "python_version": "3.9.13",
    "system": "Linux"
  },
  "plugins": [
    {
      "plugin": "mccabe",
      "version": "0.7.0"
    },
    {
      "plugin": "pycodestyle",
      "version": "2.9.0"
    },
    {
      "plugin": "pyflakes",
      "version": "2.5.0"
    }
  ],
  "version": "5.0.1"
}
```


### describe the problem

#### what I expected to happen

flake8 should not raise an exception if $HOME points to an invalid directory

For example, when running as the `nobody` user in a Debian-based Docker image, and $HOME points to `/nonexistent`.

#### commands ran

```console
# sudo -u nobody flake8
Traceback (most recent call last):
  File "/usr/local/bin/flake8", line 8, in <module>
    sys.exit(main())
  File "/usr/local/lib/python3.9/site-packages/flake8/main/cli.py", line 22, in main
    app.run(argv)
  File "/usr/local/lib/python3.9/site-packages/flake8/main/application.py", line 336, in run
    self._run(argv)
  File "/usr/local/lib/python3.9/site-packages/flake8/main/application.py", line 324, in _run
    self.initialize(argv)
  File "/usr/local/lib/python3.9/site-packages/flake8/main/application.py", line 296, in initialize
    cfg, cfg_dir = config.load_config(
  File "/usr/local/lib/python3.9/site-packages/flake8/options/config.py", line 73, in load_config
    config = _find_config_file(pwd)
  File "/usr/local/lib/python3.9/site-packages/flake8/options/config.py", line 26, in _find_config_file
    home_stat = _stat_key(home) if home != "~" else None
  File "/usr/local/lib/python3.9/site-packages/flake8/options/config.py", line 19, in _stat_key
    st = os.stat(s)
FileNotFoundError: [Errno 2] No such file or directory: '/nonexistent'
```

### Additional contract requirements

- When `$HOME` points to a nonexistent directory, the `flake8` command must return exit status `0`.
