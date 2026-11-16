ENH: Remove processed `depends_on` and `produces` markers from task function.
#### Is your feature request related to a problem?

When a generator is used to provide arguments in a single run of a parametrization and the build is parallelized, the following issue occurs: https://github.com/pytask-dev/pytask-parallel/issues/35.

A small reproducible example is:

```python
import pytask

@pytask.mark.parametrize("produces", [
    ((x for x in ["out.txt", "out_2.txt"]),),
    ["in.txt"],
])
def task_example(produces):
    for p in produces:
        p.write_text("hihi")
```

When pytask-parallel attempts to pickle the task function, the generator is empty but still there and cannot be pickled.

```
(Pdb) session.tasks[0].function.pytaskmark
[Mark(name='produces', args=(<generator object <genexpr> at 0x0000021C7D05A9E0>,), kwargs={})]
(Pdb) session.tasks[0].function.pytaskmark[0].args
(<generator object <genexpr> at 0x0000021C7D05A9E0>,)
(Pdb) session.tasks[0].function.pytaskmark[0].args[0]
<generator object <genexpr> at 0x0000021C7D05A9E0>
(Pdb) !list(session.tasks[0].function.pytaskmark[0].args[0])
[]
```

#### Describe the solution you'd like

For other markers we already remove them from the function after they are processed. For example, `@pytask.mark.parametrize` is removed.

#### API breaking implications

Good question! Don't expect issues.

#### Describe alternatives you've considered

None
