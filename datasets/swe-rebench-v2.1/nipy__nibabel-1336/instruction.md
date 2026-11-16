NIfTI Extension redesign
Right now the definition of `Nifti1Extension` is (simplified):

```python
class Nifti1Extension:
    def __init__(self, code, content):
        self.code = code
        self._content = self._unmangle(content)

    def get_content():
        return self._content
```

This means that the return type of `get_content()` depends on the subclass, violating the Liskov substitution principle and generally making it difficult to reason about the value of `extension.get_content()` without either inspecting the type of `extension` or `extension.get_content()`.

In #1327 I've found that there are several places in our tests where we've assumed that `get_content()` returns `bytes`, so it is likely that downstream users will also be broken. This seems like an opportunity to redesign.

Instead we could consider following the lead of `requests.Response`/`httpx.Response` and provide a `.content` property that is always `bytes`, a `.text` property that is always `str` (raising an error if decoding fails) and a `.json()` method that decodes the JSON object, which can fail if the contents are not valid JSON.

[HIDDEN]

This could sit alongside the old, variable-type `get_content()`.

I haven't fully thought through what we want to do for extensions that need to expose complex data types, like pydicom `Dataset`s or `Cifti2Header`s. I'll experiment a little with this with typing to make sure that what I do fits in with typed Python. Probably something like:

[HIDDEN]

Interested in feedback. Will open a PR with some initial work once I have something that typechecks and tests.

### Additional contract requirements

- `Nifti1Extension` in module `nibabel.nifti1` provides a public method `get_object()` that returns the extension content in its runtime representation; for simple extensions this is `bytes`. The existing `get_content()` method is an alias for `get_object()`.
- The `.text` property uses the extension's configured `encoding` when present and UTF-8 otherwise; decoding errors are raised to the caller.
