ENH: Allow `__tracebackhide__` to be a callable.
See https://github.com/pytest-dev/pytest/blob/483f239d01aad3328360e242ed86b081eecb7608/src/_pytest/_code/code.py#L271.

### Additional contract requirements

- When `__tracebackhide__` is callable, call it with the current exception information tuple. Hide the associated traceback frame when it returns a truthy value; otherwise, keep the frame visible.
