`alias` function for `pd.Series`
# Brief Description

<!-- Please provide a brief description of what you'd like to propose. -->

I would like to propose pd.Series.alias(new name) to allow for convenient renaming of a Series.
This comes in handy when renaming within a function, and allow for changing a Series name via a callable.
pd.Series.rename only changes the name if a scalar is passed; if a callable is passed, it is passed to the index labels, not the name of the Series. alias works only on the name, not the index labels.

# Example API

```python
series = pd.Series({'a':[1,2,3]})
series.alias('new_name')
series.alias(str.lower)
series.alias(lambda s: f"{s}_mean")
```
