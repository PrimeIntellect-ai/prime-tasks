False positive `SwallowedException` when exception is used as a receiver
<!-- The bug you're experiencing might have already be reported! -->
<!-- Please search in the [issues](https://github.com/detekt/detekt/issues) before creating one. -->

## Expected Behavior
`SwallowedException` should not trigger

## Observed Behavior
`SwallowedException` triggers

## Steps to Reproduce

Analyze following code:

```
private fun Exception.transformException(): Exception {
   return this
}

private fun demo() {
   try {
      TODO()
   } catch (e: Exception) {
      throw e.transformException()
   }
}
```

## Context

`Exception.transformException()` is functionally equivalent to the `transformException(source: Exception)` (which does not trigger this rule), so the rule should be satisfied with it.

## Your Environment
<!-- Include as many relevant details about the environment you experienced the bug in -->
* Version of detekt used: 1.23.6
