[regression] removing whitespace below shebang
```python
#!/usr/bin/env python

"""a.py"""
```

`docformatter==1.6.3` (also may possibly be `1.6.2` per https://github.com/PyCQA/docformatter/issues/186) is removing whitespace below a shebang.

`> docformatter a.py` leads to:

```python
#!/usr/bin/env python
"""a.py"""
```

`docformatter==1.5.1` didn't use to do that.

### Additional contract requirements

- Formatting a file with a shebang followed by a blank line must preserve that blank line.
