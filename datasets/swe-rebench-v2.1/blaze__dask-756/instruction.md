random states may have same seed
The current implementation of seeding the random number generator is:

```
[HIDDEN]
```

This can result in repetition of seeds => random sequences are the same, which is probably not what users intend. The reasoning is the same as the [birthday problem](https://en.wikipedia.org/wiki/Birthday_problem) in probability.

```
from __future__ import division

import numpy as np
from scipy.misc import comb, factorial


def prob_same(k, n=np.iinfo(np.int32).max):
    '''
    Compute the probability that at least two seeds are the same
    '''
    different = comb(n, k, exact=True) * factorial(k, exact=True)
    total = n ** k
    prob_all_different = different / total
    return 1 - prob_all_different
```

Here's a few figures:
```
In [246]: prob_same(1000)
Out[246]: 0.00023257080042193845

In [247]: prob_same(10000)
Out[247]: 0.023011865852016755

In [248]: prob_same(50000)
Out[248]: 0.4412591367423576
```

So if there are 50000 chunks, there's a 44% chance that a seed will be repeated. Probably no big deal for most use cases, but it would be better to not have to make this assumption.

It's possible to eliminate this by just sampling with replacement. Ie. change the implementation to something like:
```
[HIDDEN]
```

I don't know if this alternative implementation would be totally valid, since it seems like more may be required. See this [paper by L'Ecuyer](http://www.iro.umontreal.ca/~lecuyer/myftp/papers/wsc15rng.pdf). But it would effectively guarantee different seeds.

### Additional contract requirements

When random data is generated in chunks, each chunk must receive a seed distinct from the seeds assigned to the other chunks, so that chunks do not share the same random seed.
