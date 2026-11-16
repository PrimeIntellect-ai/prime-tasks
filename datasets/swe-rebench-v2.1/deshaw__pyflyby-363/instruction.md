Fix ImportDB.get_default when CWD is the root directory (PyInf#13677)
The enhancements made in commit https://github.com/deshaw/pyflyby/commit/7272bdb220e17430060ec1b83540a3fa22813a0c (Issue #346) introduced a bug where `ImportDB.get_default(None)` fails when the current working directory is the root directory. Reproducer:

```
>>> from pyflyby._importdb import ImportDB
>>> os.chdir('/')
>>> db = ImportDB.get_default(None)
ValueError: No know path are safe
```

The reason is that in this case, there are no parent directories to check. So the logic incorrectly thinks that there is no safe path.
