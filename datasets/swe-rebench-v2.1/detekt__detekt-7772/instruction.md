IgnoredReturnValue should not flag ignored `Nothing`
Rule: `IgnoredReturnValue`
Change: Ignore unhandled return values of type `Nothing`

## Expected Behavior of the rule

As far as I can tell, only `Unit` is never checked by this rule. I propose adding `Nothing` to that list. In practice, it is even less of a normal return value than `Unit` (which is an object an can be assigned to variables), so I can't think of any downsides. As it stands, this is a warning:

```
# detekt.yml
  IgnoredReturnValue:
    active: true
    restrictToConfig: false
    returnValueAnnotations: []
    returnValueTypes: []
    ignoreReturnValueAnnotations: []
    ignoreFunctionCall: []
```

```
fun foo(): Int {
  TODO() // The call TODO is returning a value that is ignored. [IgnoredReturnValue]
}
```

## Context

I think this should avoid false positives for situations were `IgnoredReturnValue` is in heavy use.

This is basically the opposite of #6661 (requiring specific types to _always_ be checked, but which seems to have been implemented already by defining the `returnValueTypes` config property), so maybe there is some overlap on the implementation side as well.
