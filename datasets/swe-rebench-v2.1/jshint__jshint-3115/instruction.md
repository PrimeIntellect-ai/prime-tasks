Comparison operators `==`/`!=` reported too aggressively
The `eqeqeq` option's description states, "This options prohibits the use of ==
and != in favor of `===` and `!==`." Enabling it will cause JSHint to issue
warning W118 for offending code. However, JSHint will issue a separate warning
(W041) if either side of the comparison is a "falsey" literal value,
*regardless of the value of the `eqeqeq` option*.

**If you are a contributor looking to submit a fix for this bug**, [HIDDEN] This is a shame because it makes JSHint less strict by default, but
the current behavior is inconsistent and confusing. And while the warning
message for W041 is far more descriptive (and therefore a better choice to keep
around), we can't change W118 in-place outside of a major version release. This
should be relatively straightforward, so I'm marking this issue as a "good
first bug."

**If you are a user struggling with this bug today**, disable W041 in your
project configuration, either with an in-line directive:

```js
// jshint -W041
```

Or within a JSHint configuration file:

```js
{
  "-W041": true
}
```

### Additional contract requirements

- Do not emit warning W041 at all, including for any `==` or `!=` comparison, regardless of operand values or the `eqeqeq` option.
