Allow mixed configurations for rules that use `valuesWithReason`
## Expected Behavior
I can use config like:

```yaml
  ForbiddenMethodCall:
    active: true
    methods:
      - 'kotlin.io.print'
      - value: 'org.jetbrains.kotlin.analysis.project.structure.builder.buildKtLibraryModule'
        reason: 'Not performant due to KT-71706. Use buildKspLibraryModule instead.'
```

## Current Behavior
```
> Analyzing C:\Users\user\IdeaProjects\detekt\detekt-test-utils\src\main\kotlin\io\github\detekt\test\utils\CompileExtensions.kt led to an exception.
  Location: io.gitlab.arturbosch.detekt.api.ConfigPropertyKt.getValuesWithReasonOrDefault(ConfigProperty.kt:160)
  The original exception message was: Only lists of strings or maps with keys 'value' and 'reason' are supported. 'methods' is invalid.
```

To avoid it, I have to do this:
```yaml
  ForbiddenMethodCall:
    active: true
    methods:
      - value: 'kotlin.io.print'
      - value: 'org.jetbrains.kotlin.analysis.project.structure.builder.buildKtLibraryModule'
        reason: 'Not performant due to KT-71706. Use buildKspLibraryModule instead.'
```

But requiring `value: ` for all listed methods should not be necessary if I only want to set the reason for a subset of methods.

I can also just leave out the reason:
```yaml
  ForbiddenMethodCall:
    active: true
    methods:
      - 'kotlin.io.print'
      - 'org.jetbrains.kotlin.analysis.project.structure.builder.buildKtLibraryModule'
```

But this isn't a good workaround because the reason is lost.

## Context
Configure value and reason only for methods that really need it.
