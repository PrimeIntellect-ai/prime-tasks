MagicNumber rule does not trigger for unsigned literals
<!-- The bug you're experiencing might have already be reported! -->
<!-- Please search in the [issues](https://github.com/detekt/detekt/issues) before creating one. -->

## Expected Behavior

The `MagicNumber` rule should be reporting 'magic numbers' written as unsigned number literals (for example, `65520U`).

## Observed Behavior

If my code contains a 'magic number' written as an unsigned literal, the rule does not trigger. Example:

```kotlin
    a = 65520U // does not trigger
    b = 0xFFF0U // also 'fine'
    c = 65520.toUInt() // now it triggers
    d = 0xFFF0.toUInt() // triggers on this one too
```

## Steps to Reproduce
<!-- Provide a link to a live example, or an unambiguous set of steps to -->
<!-- reproduce this bug. Include code to reproduce, if relevant -->

See **Observed Behavior** above.

## Context
<!-- How has this issue affected you? What are you trying to accomplish? -->
<!-- Providing context helps us come up with a solution that is most useful in the real world -->

N/A (should be obvious from the rule's purpose)

## Your Environment
<!-- Include as many relevant details about the environment you experienced the bug in -->
* Version of detekt used: 1.23.8
* Version of Gradle used (if applicable): 8.14.1
* Operating System and version: Windows 11 Pro 24H2

My `detekt.yaml` has this:

```yaml
  MagicNumber:
    ignoreCompanionObjectPropertyDeclaration: false
    ignoreNamedArgument: false
    ignoreExtensionFunctions: false
```
