ClassOrdering rule prints incorrect message
<!-- The bug you're experiencing might have already be reported! -->
<!-- Please search in the [issues](https://github.com/detekt/detekt/issues) before creating one. -->

## Expected Behavior
<!-- Tell us what should happen -->

## Observed Behavior
<!-- Tell us what happens instead of the expected behavior -->

## Steps to Reproduce
<!-- Provide a link to a live example, or an unambiguous set of steps to -->
<!-- reproduce this bug. Include code to reproduce, if relevant -->
Example class that can triggers this behavior
```
class ExampleClass {

    var var1 = 1

    fun bar() {

    }

    var var2 = 2

    init {
    }

    companion object {
    }
}
```

## Context
<!-- How has this issue affected you? What are you trying to accomplish? -->
<!-- Providing context helps us come up with a solution that is most useful in the real world -->
Sometimes ClassOrdering Rule print you incorrect messages. For example in code above it types "ClassOrdering: method `bar()` should be declared before companion object." despite bar() already declared before companion object. The correct error here is "method `bar()` should be declared after property declarations and initializer blocks"

## Your Environment
<!-- Include as many relevant details about the environment you experienced the bug in -->
* Version of detekt used: 1.23.6
* Version of Gradle used (if applicable):
* Gradle scan link (add `--scan` option when running the gradle task):
* Operating System and version:
* Link to your project (if it's a public repository):
