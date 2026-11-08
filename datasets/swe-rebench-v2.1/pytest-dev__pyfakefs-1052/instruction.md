RuntimeError when call os.remove during os.scandir
- The Operating System
macos 10.15

- The Python version
3.7.5

- The Module version
pytest 7.4.0
pyfakefs 5.5.0

- A minimal example to reproduce the problem (preferably in the form of a failing test)
```python
import os


def test_file_removed_during_scandir(fs):
    fs.create_file('/wls/1.log')
    fs.create_file('/wls/2.log')
    with os.scandir('/wls') as it:
        for entry in it:
            if entry.is_file():
                os.remove(entry.path)
    assert not os.path.exists('/wls/1.log')
```


- The stack trace in case of an unexpected exception.
```
    File ".../test.py", line 7, in test_file_removed_during_scandir
        for entry in it:
    File ".../pyfakefs/fake_scandir.py", line 149, in __next__
        entry = self.entry_iter.__next__()
RuntimeError: dictionary changed size during iteration
```

[HIDDEN]

### Additional contract requirements

- Iterating over `os.scandir` results must allow files encountered during iteration to be removed without raising `RuntimeError`, and the iteration must be able to complete.
