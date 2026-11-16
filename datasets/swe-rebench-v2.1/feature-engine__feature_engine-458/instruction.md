Would be useful to have a simple categorical levels encoder
It would be useful if there could be a class that would encode `object` / `category` and similar dtypes into `pd.Categorical`, while remembering the categories / encodings / levels that were used when calling `transform` later, but without applying any further transformation like one-hot (akin to R's `factor(data, levels)`).

### Additional contract requirements

Expose this transformer publicly as `MatchCategories` in the preprocessing package. By default, it processes object and pandas categorical columns; arbitrary numeric columns are not required to be converted. The resulting columns use pandas categorical dtype, retain the category levels learned from the data supplied to `fit` when later transformed, and do not undergo an additional encoding such as one-hot encoding.
