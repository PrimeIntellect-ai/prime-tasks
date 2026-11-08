Add add_count and add_total functions
I know there is functionality with groupby_agg here, so I have been going back and forth on this one.  But like the tidyverse there are helper functions the are more direct like tally or add_count, where you could use summarize() and count() or n() together to get the same output.

I am not deeply invested in this suggestion, so if you think that groupby_agg can work here alone, I am fine with that.

Here are the two proposed functions I could possibly add:

add_count function
```
@pf.register_dataframe_method
def add_count(df: pd.DataFrame(), count_column: str, new_column_name: str, include_na: bool):
    """Add countby column on target column"""

    if include_na == True:
        df[new_column_name] = df.groupby([count_column])[count_column].transform('count')
        num = df[new_column_name].isna().sum()
        df[new_column_name].fillna(num, inplace= True)
        return df

    else:
        df[new_column_name] = df.groupby([count_column])[count_column].transform('count')
        return df

```

add_total function
```
@pf.register_dataframe_method
def add_total(df: pd.DataFrame(), sum_columns: list, new_column_name: str, axis: int, skipna: bool):
    """Add countby column on target column"""

    if axis == 1:
        df[new_column_name] = df[sum_columns].sum(axis= axis, skipna = skipna )
        return df

    else:
        df[new_column_name] = df[sum_columns].sum(axis= axis, skipna = skipna ).sum()
        return df
```

### Additional contract requirements

- The per-value counting functionality, including handling of missing values in
  the grouping key, must be available through the existing `groupby_agg` method.
- `groupby_agg` must retain rows whose grouping key contains missing values.
  When any column named in `by` contains nulls, those rows must not be dropped
  from the result. Rows whose grouping key is null must be grouped together and
  included in the aggregation, so that the new column holds the aggregated
  value for that group.
