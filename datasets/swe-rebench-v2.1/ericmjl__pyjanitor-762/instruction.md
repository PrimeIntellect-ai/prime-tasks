Truncate long column names ?
# Brief Description

Often when exporting CSVs from questionnaires, the column names are paragraphs, or really long strings.

I would like to propose that we add an option to `clean_names` that truncates long sentence column names to something shorter. This would be useful not just in looking at the df in a notebook, but also when renaming it. Currently my workaround is to print the column names, and then use a dictionary with existing:new column names that gets passed into the rename column method.

# Example API

```python
cleaned_df = (
    pd.read_csv('data/Learning Log #1 Survey Student Analysis Report.csv')
    .clean_names(remove_special = True, truncate_limit = 50)
    .remove_empty()
)
```

^ the tuncate_limit can be defaulted to None to avoid truncating, and a number enables the maximum number of characters in the column.
