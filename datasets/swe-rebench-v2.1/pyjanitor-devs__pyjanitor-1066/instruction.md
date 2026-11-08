Incorrectly modified output of `count_cumulative_unique` when `case_sensitive` is turned off
# Brief Description

The `case_sensitive` parameter of `count_cumulative_unique` when set to False, would modify the column which is being counted, and this change is then (wrongly) propagated to the output.

The implementation is currently written like so:
[HIDDEN]
Which modifies the column_name for the intermediate calculation of `count_cumulative_unique`, which is incorrect. See MWE.

# Minimally Reproducible Code

```python
In [4]: df = pd.DataFrame({"ccu": np.array(["a", "b", "c", "A", "B", "C", "a", "b", "c"])})

In [5]: df
Out[5]:
  ccu
0   a
1   b
2   c
3   A
4   B
5   C
6   a
7   b
8   c

In [6]: df.count_cumulative_unique("ccu", "counting", case_sensitive=False)
Out[6]:
  ccu  counting
0   a         1
1   b         2
2   c         3
3   a         3
4   b         3
5   c         3
6   a         3
7   b         3
8   c         3
```
Note that the `ccu` column in the original df has upper case letters, but the `ccu` column in the output does not. Changes made to the dataframe for intermediate calculations (i.e., `str.lower()`) should not be propagated to the final output.
