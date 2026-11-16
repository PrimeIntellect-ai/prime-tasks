[BUG] Tilde not included in link regex
The following doesn't highlight pas the `~`
```
>>> from rich import print
>>> print("http://127.0.0.1/~foo")
http://127.0.0.1/~foo
```
