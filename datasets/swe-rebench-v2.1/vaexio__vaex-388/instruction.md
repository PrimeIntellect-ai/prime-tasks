ds.join with how='right' automatically sets inplace=True
For how='right', inplace is apparently automatically activated.
Using inplace=False does not alter this anymore.
I guess this is a small bug.

ds1.join(ds2, left_on='a', right_on='b', how='right', inplace=False)
returns:

\# | b | y | a | x
-- | -- | -- | -- | --
0 | 'a' | 1 | 'a' | 1
1 | 'b' | 4 | 'b' | 2
2 | 'd' | 9 | masked | masked

For:
ds1

\# | a | x
-- | -- | --
0 | 'a' | 1
1 | 'b' | 2
2 | 'c' | 3

and
ds2

\# | b | y
-- | -- | --
0 | 'a' | 1
1 | 'b' | 4
2 | 'd' | 9

### Additional contract requirements

- The join is exposed as `DataFrame.join(other, on=None, left_on=None, right_on=None, how='inner', lprefix='', rprefix='', lsuffix='', rsuffix='', inplace=False)`, which returns a DataFrame.
- A right join (`how='right'`) with `inplace=False` returns a new DataFrame that contains the joined columns from both input DataFrames. Columns that exist in both inputs are disambiguated: the calling DataFrame's columns use `lprefix`/`lsuffix` and `other`'s columns use `rprefix`/`rsuffix`. For example, joining on a shared column `x` with `rsuffix='_r'` yields both `x` (from the calling DataFrame) and `x_r` (from `other`).
- When `inplace=False`, neither input DataFrame is modified by the join.
