Add `evaluation details` to `finally` hook stage
Add `evaluation details` to `finally` hook stage.

### Notes

This breaks the signature of the `finally` stages based on [this spec enhancement](https://github.com/open-feature/spec/pull/280). It is **not** considered a breaking change to the SDK because hooks are marked as experimental in the spec, and the change has no impact on known hooks.

```psuedo
- finally(hookContext, hookHints)
+finally(hookContext, evaluationDetails, hookHints)
```

## Acceptance criteria:

- finally hook stage modified
- associated tests

## Follow ups:

- update contribs
