Have a more helpful message when description-file is missing
I created a `pyproject.toml` file with a `description-file = "README.md"` but didn't create the README file. flit presented me with a not-so-direct message about a missing `README.md`. It would be nice if flit had suggested something like "did you not create a README.md file", instead of presenting a traceback (see also #174).

What I got currently:

```
Traceback (most recent call last):
  File "/Users/pradyunsg/.venvwrap/venvs/flit-trial/bin/flit", line 11, in <module>
    sys.exit(main())
  File "/Users/pradyunsg/.venvwrap/venvs/flit-trial/lib/python3.6/site-packages/flit/__init__.py", line 101, in main
    main(args.ini_file, formats=set(args.format or []))
  File "/Users/pradyunsg/.venvwrap/venvs/flit-trial/lib/python3.6/site-packages/flit/build.py", line 40, in main
    sb = SdistBuilder(ini_file)
  File "/Users/pradyunsg/.venvwrap/venvs/flit-trial/lib/python3.6/site-packages/flit/sdist.py", line 151, in __init__
    self.ini_info = inifile.read_pkg_ini(ini_path)
  File "/Users/pradyunsg/.venvwrap/venvs/flit-trial/lib/python3.6/site-packages/flit/inifile.py", line 53, in read_pkg_ini
    res = prep_toml_config(d, path)
  File "/Users/pradyunsg/.venvwrap/venvs/flit-trial/lib/python3.6/site-packages/flit/inifile.py", line 90, in prep_toml_config
    md_dict, module = _prep_metadata(d['metadata'], path)
  File "/Users/pradyunsg/.venvwrap/venvs/flit-trial/lib/python3.6/site-packages/flit/inifile.py", line 187, in _prep_metadata
    with description_file.open(encoding='utf-8') as f:
  File "/usr/local/Cellar/python/3.6.5/Frameworks/Python.framework/Versions/3.6/lib/python3.6/pathlib.py", line 1181, in open
    opener=self._opener)
  File "/usr/local/Cellar/python/3.6.5/Frameworks/Python.framework/Versions/3.6/lib/python3.6/pathlib.py", line 1035, in _opener
    return self._accessor.open(self, flags, mode)
  File "/usr/local/Cellar/python/3.6.5/Frameworks/Python.framework/Versions/3.6/lib/python3.6/pathlib.py", line 387, in wrapped
    return strfunc(str(pathobj), *args)
FileNotFoundError: [Errno 2] No such file or directory: 'README.md'
```
