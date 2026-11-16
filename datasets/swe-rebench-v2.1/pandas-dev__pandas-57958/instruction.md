BUG: regression, is_unique is incorrect since pandas 2.1.0
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
print("pandas version", pd.__version__)

values = [1, 1, 2, 3, 4]
index = pd.Index(values)

print("===========")
print(index)
print("is_unique=", index.is_unique)

filtered_index = index[2:].copy()

print("===========")
print(filtered_index)
print("is_unique=", filtered_index.is_unique)


index = pd.Index(values)
filtered_index = index[2:].copy()

print("===========")
print(filtered_index)
print("is_unique=", filtered_index.is_unique)
```


### Issue Description

Hello,

We found a regression, `index.is_unique` is incorrect since pandas 2.1.0.

I looked for open issues but did not find any fix or existing discussion.
Having a look at the changelog, there were lots of changes in 2.1.0 to introduce copy-on-write optimizations on the index.
I think the issue could be related to that, my best guess, maybe `index[2:]` cached something from the original `index` that is no longer correct?

Attaching a simple repro, it's very easy to reproduce. :)

Thank you.

### Expected Behavior

```
pandas version 1.5.3
===========
Int64Index([1, 1, 2, 3, 4], dtype='int64')
is_unique= False
===========
Int64Index([2, 3, 4], dtype='int64')
is_unique= True
===========
Int64Index([2, 3, 4], dtype='int64')
is_unique= True
```

```
pandas version 2.2.1
===========
Index([1, 1, 2, 3, 4], dtype='int64')
is_unique= False
===========
Index([2, 3, 4], dtype='int64')
is_unique= False    # <---------------- INCORRECT
===========
Index([2, 3, 4], dtype='int64')
is_unique= True
```


### Installed Versions

tested on:

* pandas 1.5.3: PASS
* pandas 2.0.0: PASS
* pandas 2.0.3: PASS
* pandas 2.1.0: INCORRECT
* pandas 2.1.4: INCORRECT
* pandas 2.2.1 (latest): INCORRECT
