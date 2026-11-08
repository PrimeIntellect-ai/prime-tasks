`filter()` assumes non-starred `dict` as `keep` kwarg
# Observed (user) error

Just ran into a stupid error where I used `df.filter(dict(foo='bar')` instead of `df.filter(**dict(foo='bar')`, so rather than applying the expected `foo='bar'` rule, the function interprets the dict as the `keep` kwarg.

# Suggested solution

[HIDDEN]

### Additional contract requirements

- `filter()` must raise an error when `keep` is not a boolean, including when a non-starred dictionary is passed positionally and interpreted as `keep`.
