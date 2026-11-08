Lektor cached venv is broken on macOS with Python installed via Homebrew
I'm using the latest version (Lektor-3.4.0b9.dev7+gbfce91a.d20230827 as of now).

python3 is installed via homebrew (`python@3.11`) and is symlinked:

`/usr/local/bin/python3` -> `/usr/local/Cellar/python@3.11/3.11.5/bin/python3` -> ... -> `/usr/local/Cellar/python@3.11/3.11.5/Frameworks/Python.framework/Versions/3.11/bin/python3.11`

I have created a venv using `python3 -m venv env`, everything worked fine in that venv until I installed a plugin (`lektor plugins add lektor-index-pages`). After that, trying to run the `lektor server` started raising an exception:
```
...
  File "/Users/igor/.virtualenvs/lektor/lib/python3.11/site-packages/lektor/packages.py", line 125, in create
    EnvBuilder(upgrade_deps=upgrade_deps, **options).create(self.path)
...
subprocess.CalledProcessError: Command '['/Users/igor/Library/Caches/Lektor/venvs/d63a0228b40929c7189d2c99d18e960b/bin/python3.11', '-m', 'ensurepip', '--upgrade', '--default-pip']' died with <Signals.SIGABRT: 6>.
```

When I tried to run python3 using that path, I saw this error:
```
dyld[34820]: Library not loaded: @loader_path/../../../../Python.framework/Versions/3.11/Python
  Referenced from: <430E089A-35B0-314B-9FD1-1E60F9CE5756> /Users/igor/Library/Caches/Lektor/venvs/d63a0228b40929c7189d2c99d18e960b/bin/python3.11
  Reason: tried: '/Users/igor/Library/Caches/Lektor/venvs/d63a0228b40929c7189d2c99d18e960b/bin/../../../../Python.framework/Versions/3.11/Python' (no such file), '/Library/Frameworks/Python.framework/Versions/3.11/Python' (no such file), '/System/Library/Frameworks/Python.framework/Versions/3.11/Python' (no such file, not in dyld cache)
[1]    34820 abort
```

So, looks like the homebrew version of Python was built with relative paths in mind and when EnvBuilder copies that binary to another path, things go south.

[HIDDEN]

This has solved the issue for me - now, when Lektor creates a cached venv, it symlinks the used python binary in there and everything seems to work fine.

I've never heard of Lektor until today and I don't feel comfortable with making a pull request since my fix could break something else. Sorry!

### Additional contract requirements

- `VirtualEnv.create` in `lektor.packages` accepts a `symlinks` keyword argument. When it is true, the Python interpreter in the created environment is symlinked rather than copied; when it is false, the interpreter is copied.
- The default value of `symlinks` is true on non-Windows platforms and false on Windows.
