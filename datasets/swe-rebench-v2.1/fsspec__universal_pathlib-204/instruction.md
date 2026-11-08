Problem with opening local file with "compression=..."
See behavior difference with "file://filename" uri vs "filename" uri with compression.

```
>>> print(upath.__version__)
0.1.4
>>> a = UPath('abc.json.gz')
>>> a.open('wb', compression='gzip')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
TypeError: open() got an unexpected keyword argument 'compression'
>>>
>>> a = UPath('file:///tmp/abc.json.gz')
>>> a.open('wb', compression='gzip')
<gzip fsspec.implementations.local.LocalFileOpener object at 0x1028548b0 0x1034b1f40>
```

### Additional contract requirements

- `UPath.open` accepts the pathlib-compatible signature
  `open(mode="r", buffering=-1, encoding=None, errors=None, newline=None, **fsspec_kwargs)`
  and returns a file object that behaves like the built-in `open()`: a text stream
  for text modes and a binary stream for binary modes.
- Any extra keyword arguments are forwarded to the underlying fsspec filesystem, so
  options such as `compression` and `block_size` are accepted and take effect.
- In text mode, `encoding`, `errors` and `newline` are honoured.
- Supplying the same argument both positionally and as a keyword raises `TypeError`.
