Add the ability to test and sort timestamps to be monotonic in a pandas data frame
# Brief Description

Following up on #703, this issue seeks to introduce the ability to sort the timestamps in a pandas data frame monotonically

I would like to propose...

# Example API
```python
def _test_for_monotonicity(
        df: pd.DataFrame,
        column_name: str = None,
        direction: str = 'increasing'
) -> bool:
    """
    Tests input data frame for monotonicity.

    Check if the data is monotonically increasing or decreasing.
    Direction is dependent on user input.
    Defaults to increasing

    :param df: data frame to be tested for monotonicity
    :param column_name: needs to be specified if and only if the date time is not in index.
        Defaults to None.
    :param direction: specifies the direction in which monotonicity is being tested for.
        Defaults to 'increasing'
    :return: single boolean flag indicating whether the test has passed or not
    """

def sort_monotonically(
        df: pd.DataFrame,
        column_name: str = None,
        direction: str ='increasing'
) -> pd.DataFrame:
    """
    Sorts data frame monotonically.
    It assumes the data frame has an index of type pd.DateTimeIndex when index is datetime.
    If datetime is in a column, then the column is expected to be of type pd.Timestamp

    :param df: data frame to sort monotonically
    :param column_name: needs to be specified if and only if the date time is not in index.
        Defaults to None
    :param direction: specifies the direction in which monotonicity is being tested for.
        Defaults to 'increasing'
    :return: data frame with its index sorted
    """


# more examples below
# ...
```

### Additional contract requirements

The public API is the pandas-flavor DataFrame method
`DataFrame.sort_timestamps_monotonically(direction="increasing", strict=False)`.
It sorts the DataFrame's index in the requested direction
(`"increasing"` or `"decreasing"`).
When `strict=True`, duplicate timestamps are removed, keeping the first occurrence.
If the index is already monotonic in the requested direction, the DataFrame is returned unchanged.
