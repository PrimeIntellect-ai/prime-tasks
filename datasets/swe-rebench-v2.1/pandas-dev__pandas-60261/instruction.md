ENH: set `__module__` on top-level public objects
Currently the repr of the DataFrame class (and any other class or method in the main namespace) shows the "full code path" of where the object is actually defined:

```
>>> import pandas as pd
>>> pd.DataFrame
<class 'pandas.core.frame.DataFrame'>
```

while we _could_ also make it show the code path of how it is publicly exposed (and expected to be imported and used):

```
>>> pd.DataFrame
<class 'pandas.DataFrame'>
```

The above can be achieved by setting the `__module__` attribute on the classes and methods. In numpy they already do this for several years, and so the repr of top-level functions or objects shows "numpy.<..>", and not things like "numpy.core.multiarray..". The main PR in numpy that implemented this: https://github.com/numpy/numpy/pull/12382

I think the main benefits are:

* Reduce the visual noise and hide implementation details for users (no regular user needs to know that DataFrame class is defined in pandas/core/frame.py)
* Avoid that people tend to incorrectly import from where it is defined (i.e. discourage `from pandas.core.frame import DataFrame`, a pattern that we often see in downstream packages). I think this would also help for making `pandas.core` private (and potentially renaming it, xref https://github.com/pandas-dev/pandas/issues/27522, cc @rhshadrach)

The main disadvantage is that we thus mask where an object lives, which makes it harder for contributors to figure that out. On the draft PR, @jbrockmendel also commented:

> > inspired by similar implementation in numpy
>
> Whenever I try to figure out how something in numpy works I have a hard time finding out where something is defined because they use patterns like `from foo import *` at the top level. I don't know if the pattern in this PR contributes to that pain point, but my spidey sense is tingling that it might.

This does not change any `*` imports (it only changes the _visual_ repr), but that aside, it certainly hides a bit more where something is defined, making it harder to find the location (the file) in the source code. But this masking is the purpose of the proposal, with the idea that this is better for users (see bullet points above). I certainly comes with the drawback for contributors, but in making the trade-off, there are much more users, so I would personally go with prioritizing that use case (and for contributors, there are still many other ways to find where something is defined: looking at our imports in the codebase, searching for "class DataFrame", ...).
