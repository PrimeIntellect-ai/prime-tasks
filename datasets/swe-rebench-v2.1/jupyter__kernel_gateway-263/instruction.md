JSONErrorsMixin not returning correct results after Notebook 5.2.0 is installed
This is related to [Notebook Issue 2942](https://github.com/jupyter/notebook/issues/2942).

One of the changes in Notebook 5.2.0 was the removal of the `@json_errors` decorator via [PR 2853](https://github.com/jupyter/notebook/pull/2853).  Instead, much of the equivalent code was moved into the `APIHandler.write_error` method.  [HIDDEN]  `JSONErrorsMixin.write_error` doesn't handle the traceback functionality present in `@json_errors` (or `APIHandler`) and results in the breakage of the `TestCustomDefaultKernel` test.

Since `APIHandler.write_error` should be doing the equivalent of `@json_errors`, I commented out the subclassing of `JSONErrorsMixin` from some of the handler classes, but then encountered a different set of test errors - these relating to no `reason` field on HTTP errors.  It turns out that one of the pieces of functionality in `@json_errors` not "transferred" to `APIHandler` was the appropriate setting of the reason code.

Since its not sufficient to fallback to using `APIHandler`, we should make the appropriate changes to `JSONErrorsMixin.write_error` in order to bridge the gap between Notebook 5.2 GA and the future release that addresses the APIHandler/reason issue.

### Additional contract requirements

- JSON error responses should include traceback information when traceback reporting applies.
- HTTP error responses should include an appropriately set `reason` field.
