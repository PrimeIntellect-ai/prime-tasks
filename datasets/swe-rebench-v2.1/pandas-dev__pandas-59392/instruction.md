ENH: Reduce type requirements for the subset parameter in drop_duplicates/duplicated
### Feature Type

- [ ] Adding new functionality to pandas

- [X] Changing existing functionality in pandas

- [ ] Removing existing functionality in pandas


### Problem Description

I would like to pass a set to drop_duplicates like so:

```
df = get_some_df()
subset = {"column1", "column3"}
df_dropped = df.drop_duplicates(subset=subset)
```
According to type hints, `subset` is a `Hashable | Sequence[Hashable] | None`. The documentation says "column label or sequence of labels, optional".

The problem is, I would like to pass a set of columns. The name `subset` suggests that should be ok. And it does work indeed. **However, a `set` is not a `Sequence`.**

Can the requirements be lowered? Maybe to `Collection`? (or even `Iterable`, but that might come with problems).

Looking at the code: https://github.com/pandas-dev/pandas/blob/v2.2.2/pandas/core/frame.py#L6935

[HIDDEN]

Am I missing anything or could this Sequence be make a Collection?



### Feature Description

[HIDDEN]

### Alternative Solutions

no alt solution required

### Additional Context

_No response_

### Additional contract requirements

- `DataFrame.duplicated` must accept any iterable of hashable column names for
  `subset`, exactly like `DataFrame.drop_duplicates` (for example a `set`).
- The `subset` parameter annotation in the public signatures of both
  `DataFrame.drop_duplicates` and `DataFrame.duplicated` is
  `Hashable | Iterable[Hashable] | None`.
- The `subset` documentation for both `DataFrame.drop_duplicates` and
  `DataFrame.duplicated` must describe the parameter as a column label or
  iterable of labels (the phrase "iterable of labels").
