unsorted-dict-items suggests strange ordering for 'exports'
Am I missing something with regards to the suggested ordering warned by `unsorted-dict-items`?

In a list of attributes, buildifier suggests the following ordering:

```
        "dynamic_deps"
        "linkopts"
        "preloaded_deps"
        "visibility_file"
        "exports"
        "_cc_toolchain"
```

`exports` seems out of place, here. If we rename it to `exportsfoo`, buildifier suggests a sensible ordering (`exportsfoo` should go before `linkopts`)

IIUC, the [documentation](https://github.com/bazelbuild/buildtools/blob/master/WARNINGS.md#dictionary-items-should-be-ordered-by-their-keys) for this warning only remarks potentially overriding the ordering.
