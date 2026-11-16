Use Unknown logical type for null columns
Based off discussion in #1038, it makes more sense to infer columns that are entirely null (i.e. made entirely up of `None`, `np.nan`, or `pd.NA`) as `Unknown` logical type instead of `Double` or `Categorical`. This way, entirely null columns are all handled in a consistent manner.
