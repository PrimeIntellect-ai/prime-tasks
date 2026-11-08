AttributeError on Python 3.10
Checking a file with a syntax error on Python 3.10rc1 causes flake8 to crash with an AttributeError:

```
$ cat > foo.py
bad python:
^D
pmxbot main $ python3.10 -m pip-run flake8 -- -m flake8 foo.py
Collecting flake8
  Using cached flake8-3.9.2-py2.py3-none-any.whl (73 kB)
Collecting pycodestyle<2.8.0,>=2.7.0
  Using cached pycodestyle-2.7.0-py2.py3-none-any.whl (41 kB)
Collecting mccabe<0.7.0,>=0.6.0
  Using cached mccabe-0.6.1-py2.py3-none-any.whl (8.6 kB)
Collecting pyflakes<2.4.0,>=2.3.0
  Using cached pyflakes-2.3.1-py2.py3-none-any.whl (68 kB)
Installing collected packages: pyflakes, pycodestyle, mccabe, flake8
Successfully installed flake8-3.9.2 mccabe-0.6.1 pycodestyle-2.7.0 pyflakes-2.3.1
Traceback (most recent call last):
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/checker.py", line 478, in run_ast_checks
    ast = self.processor.build_ast()
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/processor.py", line 225, in build_ast
    return ast.parse("".join(self.lines))
  File "/Library/Frameworks/Python.framework/Versions/3.10/lib/python3.10/ast.py", line 50, in parse
    return compile(source, filename, mode, flags,
  File "<unknown>", line 1
    bad python:
    ^^^^^^^^^^
SyntaxError: invalid syntax. Perhaps you forgot a comma?

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/Users/jaraco/.local/bin/flake8", line 8, in <module>
    sys.exit(main())
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/main/cli.py", line 22, in main
    app.run(argv)
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/main/application.py", line 363, in run
    self._run(argv)
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/main/application.py", line 351, in _run
    self.run_checks()
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/main/application.py", line 264, in run_checks
    self.file_checker_manager.run()
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/checker.py", line 323, in run
    self.run_serial()
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/checker.py", line 307, in run_serial
    checker.run_checks()
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/checker.py", line 589, in run_checks
    self.run_ast_checks()
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/checker.py", line 480, in run_ast_checks
    row, column = self._extract_syntax_information(e)
  File "/Users/jaraco/.local/pipx/venvs/flake8/lib/python3.10/site-packages/flake8/checker.py", line 465, in _extract_syntax_information
    lines = physical_line.rstrip("\n").split("\n")
AttributeError: 'int' object has no attribute 'rstrip'
```

Checking the same file on Python 3.9 passes just fine:

```
pmxbot main $ python3.9 -m pip-run -q flake8 -- -m flake8 foo.py
WARNING: You are using pip version 21.2.2; however, version 21.2.3 is available.
You should consider upgrading via the '/Library/Frameworks/Python.framework/Versions/3.9/bin/python3.9 -m pip install --upgrade pip' command.
foo.py:1:5: E999 SyntaxError: invalid syntax
```
