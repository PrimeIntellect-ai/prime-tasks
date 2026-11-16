Integrate scikit-learn's `set_output` method into `TransactionEncoder`
<!--
If this is your first Issue submitted to the MLxtend Issue Tracker, please review
the code of conduct, which is available at https://rasbt.github.io/mlxtend/Code-of-Conduct/.
-->

# Describe the workflow you want to enable
In `scikit-learn` [version 1.2](https://scikit-learn.org/1.2/whats_new/v1.2.html#id8), [the `set_output` API was introduced](https://scikit-learn.org/stable/auto_examples/miscellaneous/plot_set_output.html). I would like to expose the API inside of the [`mlxtend.preprocessing.transactionencoder.TransactionEncoder`](https://rasbt.github.io/mlxtend/api_subpackages/mlxtend.preprocessing/#transactionencoder) class. This would allow the user to set the output of :method:`TransactionEncoder.fit_transform` and :method:`TransactionEncoder.transform` to a [`pandas.DataFrame`](https://pandas.pydata.org/docs/reference/api/pandas.DataFrame.html) by default, rather than having to manually create the object after transformation.

# Describe your proposed solution
My proposed solution is to define the [:method:`get_feature_names_out`](https://scikit-learn.org/stable/glossary.html#term-get_feature_names_out) in :class:`TransactionEncoder` as this is required to expose the :method:`set_output`. See [:class:`TransformerMixin`](https://scikit-learn.org/stable/modules/generated/sklearn.base.TransformerMixin.html#sklearn.base.TransformerMixin) and [Developer API for `set_output`](https://scikit-learn.org/stable/developers/develop.html#developer-api-set-output) for more details.

# Describe alternatives you've considered, if relevant
Continue using the method described in the [User Guide](https://rasbt.github.io/mlxtend/user_guide/preprocessing/TransactionEncoder/)—convert the output of the transformer to a `pandas.DataFrame` manually.

# Additional context
- This would require the minimum version of `scikit-learn` to increase from 1.0.2 to 1.2.2.
- I'm willing to take on the PR for this work.

### Additional contract requirements

- Add a public method `get_feature_names_out(self)` to
  `mlxtend.preprocessing.transactionencoder.TransactionEncoder`. After fitting,
  it returns a NumPy array of feature names, equivalent to
  the estimator's `columns_` attribute.
- `TransactionEncoder` exposes the scikit-learn `set_output(self, *, transform=None)`
  method. It returns the estimator instance (self) to allow method chaining.
- When `transform="pandas"` is selected via `set_output`, both
  `TransactionEncoder.fit_transform` and `TransactionEncoder.transform` return a
  `pandas.DataFrame` whose column names match `columns_` (equivalently
  `get_feature_names_out()`), with the same values as the default numpy output.
- The declared minimum supported scikit-learn version is at least 1.2.2.
