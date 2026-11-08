ENH support run command without `.` by default
Reading the doc, it is not always clear that one should run the command as follows:

```
benchopt run . --config pathological.yml
```

One would rather like a command like

```
benchopt run --config pathological.yml
```
to work out of the box.

### Additional contract requirements

- When no benchmark path is given, the current working directory is used as the benchmark folder.
- If the resolved benchmark folder does not contain an `objective.py` file, the command fails with a `click.BadParameter` error.


- For the nonexistent path `invalid_benchmark`, the `click.BadParameter` message must include `Path 'invalid_benchmark' does not exist.` When the folder `.` lacks `objective.py`, the message must include `The folder '.' does not contain `objective.py``; for any resolved folder lacking `objective.py`, the message must include `does not contain `objective.py``.
