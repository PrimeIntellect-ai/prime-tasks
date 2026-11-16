BUG: DataFrameGroupBy.apply ignores group_keys setting when empty
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
df = pd.DataFrame({'A': 'a a b'.split(), 'B': [1, 2, 3], 'C': [4, 6, 5]})
g1 = df.groupby('A', group_keys=False)

df = pd.DataFrame({'A': [], 'B': [], 'C': []})
g2 = df.groupby('A', group_keys=False)
g3 = df.groupby('A', group_keys=True)

r1 = g1.apply(lambda x: x / x.sum())
r2 = g2.apply(lambda x: x / x.sum())
r3 = g3.apply(lambda x: x / x.sum())

print(r1.index) # Index([0, 1, 2], dtype='int64')
print(r2.index) # Index([], dtype='float64', name='A')
print(r3.index) # Index([], dtype='float64', name='A')
```


### Issue Description

The group_keys parameter has no effect when the source dataframe is empty

### Expected Behavior

group_keys=False should not include the group keys into the index regardless of whether the source dataframe is empty
I would expect results such as:
```python
print(r2.index) # Index([], dtype='float64')
print(r2.index) # RangeIndex(start=0, stop=0, step=1)
```

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.10.11
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.22631
machine               : AMD64
processor             : Intel64 Family 6 Model 141 Stepping 1, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : es_ES.cp1252

pandas                : 2.2.3
numpy                 : 1.26.4
pytz                  : 2024.2
dateutil              : 2.9.0.post0
pip                   : 23.0.1
Cython                : None
sphinx                : None
IPython               : 8.30.0
adbc-driver-postgresql: None
...
zstandard             : None
tzdata                : 2024.2
qtpy                  : None
pyqt5                 : None

</details>
