[ENH]: Groupby Top K
# Brief Description

<!-- Please provide a brief description of what you'd like to propose. -->

I would like to propose a function that allows users to take in a dataframe and return another dataframe that has the top "k" values after grouping by another column.

This has come up multiple times at work, when I have to pick out "top protein mutants in each cluster".

Posting this here in case anybody wants to take a formal stab at it, otherwise I'll get to it later.

# Example API

```python
def groupby_topk(d: pd.DataFrame, groupby_column_name: Hashable, sort_column_name: Hashable, k: int, sort_values_kwargs: Dict) -> pd.DataFrame:
    """
    Return a dataframe that has the top "k" values per group.

    Some docstrings to flesh out:
    - Groups: defined by the "groupby" column.

    Taken inspiration from https://stackoverflow.com/a/27844045/1274908
    """
    [HIDDEN]
```

Give it a thumbs up if you're interested in seeing this too!

### Additional contract requirements

Within each group, order rows by the specified sort column according to the supplied sort options, then select the first *k* rows. The result contains the selected source rows and their other columns. The function-style `groupby_topk` API shown above must be available with its dataframe, grouping-column, sorting-column, *k*, and sort-options parameters.
