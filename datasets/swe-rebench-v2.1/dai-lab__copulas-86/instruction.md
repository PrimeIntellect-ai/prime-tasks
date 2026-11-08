seed for the random numbers generators
* Copulas version: 0.1
* Python version: 3.6.6
* Operating System: Fedora release 28 (Twenty Eight)

### Description

I was expecting the `sample` methods to allow the user to pass a seed for the random numbers generators.

### What I Did

Instead, we have to use, outside the function call, `numpy.random.seed(seed_value)` and `random.setstate(seed_value)`. This is a bad practise from a software engineering standpoint and it is very error prone because it affects the global state. Also, this can negatively impact experiment reproducibility and the debugging stages.

### Recommendations

Currently, in order to get the same sample from the sampling methods, we need to

1. invoke `np.random.seed(seed_value)`
2. invoke `random.setstate(random_state_tuple)`

outside of the sampling function being invoked (i.e. `sample`). This results in what is called, in software engineering, a **leaky abstraction**. In order to solve this issue with seed control, there are (at least) two approaches:

1. Create a parameter, in the `sample` methods, named `seed` or `random_state`.
2. Create a parameter in the constructor of classes offering the `sample` method named `seed` or `random_state` IF the distribution fit method requires some sort of stochastic process.

In scikit-learn and other popular python machine learning tools, what happens is the following

1. When a model depends on some sort of stochastic process during the fit procedure, the model class constructor allows the user to set the `random_state` value. This value can be one of 3 things: None, an integer or an instance of `numpy.random.RandomState` instance. No matter what the value is, it will be checked and processed by `sklearn.utils.check_random_state`, which will output a `numpy.random.RandomState` instance. Note that the `sklearn.utils.check_random_state` method will be invoked at the beginning of the fit method (check this example: https://github.com/scikit-learn/scikit-learn/blob/master/sklearn/tree/tree.py#L129). If you set `random_state` as an integer, every fit has to be deterministic in its behavior and output.

2. If, besides the fit method, there is another method that depends on stochastic processes (e.g. the `sample` method in `sklearn.neighbors.KernelDensity`), we are allowed to control the seed through the `random_state` parameter.

3. In other more low level APIs like scipy, the seed must be an integer or None.


I also advise against using both the `random` and `numpy.random` modules at the same time because it makes the seed management harder.


EDIT: Current fix available at https://github.com/DAI-Lab/Copulas/pull/62

### Additional contract requirements

- When sampling with a caller-supplied seed succeeds, the call must leave the process-wide NumPy random state unchanged.
- Callers can supply an integer seed when constructing a bivariate, multivariate or univariate copula model, using a keyword argument named `random_seed`, `seed` or `random_state`. Repeated sampling from the same model with that seed returns the same values.
