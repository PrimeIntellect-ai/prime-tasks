project.detect_schema() should have a pretty representation in IPython
### Feature description
In #127, we added an IPython representation for `JobsCursor` objects. I would like the same kind of behavior for `ProjectSchema` objects, with a pretty format that looks similar to the output of `signac schema`.

### Proposed solution

Add a method `_repr_html_` to `ProjectSchema`. Refer to `JobsCursor` and `Project` classes for examples.
