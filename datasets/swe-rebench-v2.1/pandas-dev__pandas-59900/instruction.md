ENH: increase verbosity on error
### Feature Type

- [ ] Adding new functionality to pandas

- [X] Changing existing functionality in pandas

- [ ] Removing existing functionality in pandas


### Problem Description

On a specific type error the error causing type is not logged in the error

### Feature Description

By replacing:
[HIDDEN]
the problem would be solved

Details can be found in [here](https://github.com/pandas-dev/pandas/pull/59649/files)

### Alternative Solutions

Use a debugger and set a break point

### Additional Context

_No response_

### Additional contract requirements

- When the `.str` accessor rejects values because they are not string-like, the resulting `AttributeError` message must identify the inferred dtype of those values.
