mcnemar(tb, exact=True) do not return None as chi2
Thanks for your wonderful work!
I noticed a bug.

<!--
If this is your first Issue submitted to the MLxtend Issue Tracker, please review
the code of conduct, which is available at http://rasbt.github.io/mlxtend/Code-of-Conduct/.
-->


<!--
Before submitting a bug, please check the recent Changelog entries at
https://github.com/rasbt/mlxtend/blob/master/docs/sources/CHANGELOG.md
and do a quick search in the Issue Tracker (https://github.com/rasbt/mlxtend/issues)
to make sure the issue hasn't been already
addressed.
-->

#### Describe the bug

<!--
Briefly describe what the bug is.
-->

`mlxtend.evaluate.mcnemar` does not return `None` as `chi2` when `exact=True`.

#### Steps/Code to Reproduce

<!--


<!--
Please add a minimal example that can help understand and reproduce the bug.
Ideally, this should be a self-contained code example that can be run
on our computer with easily accessible datasets (ideally, datasets contained
in scikit-learn or MLxtend itself).


Example:

```python
import numpy as np
from mlxtend.evaluate import bootstrap


rng = np.random.RandomState(123)
x = rng.normal(loc=5., size=100)
original, std_err, ci_bounds = bootstrap(x, num_rounds=1000, func=np.mean, ci=0.95, seed=123)
print('Mean: %.2f, SE: +/- %.2f, CI95: [%.2f, %.2f]' % (original,
                                                        std_err,
                                                        ci_bounds[0],
                                                        ci_bounds[1]))
```

If the code is too long, feel free to put it in a public gist and link
it in the issue: https://gist.github.com
-->

ref: https://rasbt.github.io/mlxtend/user_guide/evaluate/mcnemar/#example-3-mcnemars-test-for-scenario-a

```python
>>> import numpy as np
>>> from mlxtend.evaluate import mcnemar

>>> tb_a = np.array([[9959, 11], [1, 29]])
>>> tb_a
array([[9959,   11],
       [   1,   29]])
>>> chi2, _ = mcnemar(tb_a, exact=True)
```

#### Expected Results

<!-- Please paste or describe the expected results.-->

`chi2` is None.

ref: https://rasbt.github.io/mlxtend/user_guide/evaluate/mcnemar/#api
>if exact=True (default: False), chi2 is None

#### Actual Results
<!-- Please paste or specifically describe the actual output or error traceback. -->

`chi2` is not None.

```python
>>> chi2
1
```

The value comes from:

https://github.com/rasbt/mlxtend/blob/1943512dbf68ed967ec5a8941d6ce8d96288ff09/mlxtend/evaluate/mcnemar.py#L216

Unit test does not verify that the return value is None.

https://github.com/rasbt/mlxtend/blob/1943512dbf68ed967ec5a8941d6ce8d96288ff09/mlxtend/evaluate/tests/test_mcnemar_test.py#L44

The assertion should be `assert chi2p is None`

#### Versions

<!--
Please run the following snippet and paste the output below.
import mlxtend; print("MLxtend", mlxtend.__version__)
import platform; print(platform.platform())
import sys; print("Python", sys.version)
import sklearn; print("Scikit-learn", sklearn.__version__)
import numpy; print("NumPy", numpy.__version__)
import scipy; print("SciPy", scipy.__version__)
-->

MLxtend 0.21.0
macOS-10.14.6-x86_64-i386-64bit
Python 3.10.2 (v3.10.2:a58ebcc701, Jan 13 2022, 14:50:16) [Clang 13.0.0 (clang-1300.0.29.30)]
Scikit-learn 1.1.2
NumPy 1.23.3
SciPy 1.9.1

<!-- Thanks for contributing! -->
