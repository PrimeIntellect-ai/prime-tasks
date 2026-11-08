ENH: simplify id assignment using explode
The id assignment of generate_staypoints (starting from [here](https://github.com/mie-lab/trackintel/blob/8372d269c9ab2489c3a4ef7a8bf4bb04625127bb/trackintel/preprocessing/positionfixes.py#L148) ) can be simplified by using the explode function, like in [generate_trips function](https://github.com/mie-lab/trackintel/blob/8372d269c9ab2489c3a4ef7a8bf4bb04625127bb/trackintel/preprocessing/triplegs.py#L243).

Also, We can maybe generalize this process and write a generic function in util

### Additional contract requirements

Add a public function `_explode_agg(column, agg, orig_df, agg_df)` in the module `trackintel.preprocessing.util`.

- `column` is the name of the column in `agg_df` that holds list-like values to be exploded; the exploded values correspond to index values of `orig_df`.
- `agg` is the name of the column in `agg_df` that is joined back onto `orig_df`.
- `orig_df` is the DataFrame that lacks the aggregated information.
- `agg_df` is the DataFrame that holds the aggregated information.
- The function returns a `pd.DataFrame` that contains all rows and columns of `orig_df` plus the column `agg` taken from `agg_df`. Rows of `orig_df` whose index does not appear among the exploded values of `agg_df[column]` receive `NaN` in the added column.

The staypoint id assignment of `generate_staypoints` must keep assigning to each positionfix the id of the staypoint it belongs to, and leave the id missing for positionfixes that belong to no staypoint.
