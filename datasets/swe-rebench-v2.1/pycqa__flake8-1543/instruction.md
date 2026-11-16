Improvement suggestion: Add the relevant path as context when encountering exceptions in checker.py
In GitLab by @motin1 on Oct 2, 2018, 03:07

Ran into `UnicodeDecodeError: 'utf8' codec can't decode byte 0xb1 in position 81: invalid start byte` suddenly when running flake8:

```
$ flake8
Traceback (most recent call last):
  File "/path/to/project/venv/bin/flake8", line 11, in <module>
    sys.exit(main())
  File "/path/to/project/venv/lib/python2.7/site-packages/flake8/main/cli.py", line 16, in main
    app.run(argv)
  File "/path/to/project/venv/lib/python2.7/site-packages/flake8/main/application.py", line 396, in run
    self._run(argv)
  File "/path/to/project/venv/lib/python2.7/site-packages/flake8/main/application.py", line 384, in _run
    self.run_checks()
  File "/path/to/project/venv/lib/python2.7/site-packages/flake8/main/application.py", line 310, in run_checks
    self.file_checker_manager.run()
  File "/path/to/project/venv/lib/python2.7/site-packages/flake8/checker.py", line 319, in run
    self.run_parallel()
  File "/path/to/project/venv/lib/python2.7/site-packages/flake8/checker.py", line 288, in run_parallel
    for ret in pool_map:
  File "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/multiprocessing/pool.py", line 287, in <genexpr>
    return (item for chunk in result for item in chunk)
  File "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/multiprocessing/pool.py", line 668, in next
    raise value
UnicodeDecodeError: 'utf8' codec can't decode byte 0xb1 in position 81: invalid start byte
```

*Please describe the problem or feature*

Without any context of what path the checker was processing at the time of the throw exception, it was hard to understand what was causing it.

Eventually, it was discovered that flake8 encountered the utf8 decoding issue within a vendor folder that was not supposed to be scanned by flake8 to begin with. Configuring an exclude for that folder solved the issue for now, but to make this easier for others in the future, it would be great if checker.py caught exceptions and added the relevant path as context.

*Please describe how you installed Flake8*

```
git clone https://github.com/project/repo.git
cd repo
virtualenv venv
source venv/bin/activate
pip install flake8
```

*Please provide the exact, unmodified output of `flake8 --bug-report`*

```
$ flake8 --bug-report
{
  "dependencies": [
    {
      "dependency": "setuptools",
      "version": "40.4.3"
    }
  ],
  "platform": {
    "python_implementation": "CPython",
    "python_version": "2.7.10",
    "system": "Darwin"
  },
  "plugins": [
    {
      "is_local": false,
      "plugin": "flake8_isort",
      "version": "2.3"
    },
    {
      "is_local": false,
      "plugin": "mccabe",
      "version": "0.6.1"
    },
    {
      "is_local": false,
      "plugin": "pycodestyle",
      "version": "2.3.1"
    },
    {
      "is_local": false,
      "plugin": "pyflakes",
      "version": "1.6.0"
    }
  ],
  "version": "3.5.0"
}
```
