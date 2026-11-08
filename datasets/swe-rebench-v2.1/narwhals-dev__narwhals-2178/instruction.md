[Enh]: `get_native_namespace` could check several objects
When figuring out how to do support for narwhals in fairlearn, I was concerned with how to make sure that a user passes objects from the same dataframe library, which would then determine the namespace of returned objects.

I have seen there is `nw.get_native_namespace()` and I would suggest an enhancement for it similar to something we have in scikit-learn: There is a [get_namespace()](https://github.com/scikit-learn/scikit-learn/blob/5f50a8706f46e971aa053791a1441ac8a4ebd623/sklearn/utils/_array_api.py#L497) function for Array API support and you can pass multiple objects to check.

`get_native_namespace` could also error or return False if the objects don't share a common namespace.

I would find it practical for the current use case in fairlearn and I would imagine other projects would also benefit from it. Would it make sense to add a functionality like this one?
