ENH: provide nunique method on Rolling object
GroupBy objects expose a `nunique` method of Series/DataFrame (and also for `resample` it works), but Rolling does not:

```
In [89]: values = np.random.choice(np.arange(10), 100)

In [90]: s = pd.Series(values, index=pd.date_range("2019-01-01", freq='H', periods=100))

In [92]: s.groupby(pd.Grouper(freq='D')).nunique()
Out[92]:
2019-01-01    10
2019-01-02     8
2019-01-03    10
2019-01-04    10
2019-01-05     4
Freq: D, dtype: int64
```
vs

```
In [93]: s.rolling('D').apply(pd.Series.nunique, raw=False)
Out[93]:
2019-01-01 00:00:00     1.0
2019-01-01 01:00:00     2.0
2019-01-01 02:00:00     3.0
...

# or
In [95]: s.rolling('D').apply(lambda x: len(pd.unique(x)), raw=True)
Out[95]:
2019-01-01 00:00:00     1.0
2019-01-01 01:00:00     2.0
2019-01-01 02:00:00     3.0
...
```

I think it would be nice to also have this method available on `rolling` objects.
