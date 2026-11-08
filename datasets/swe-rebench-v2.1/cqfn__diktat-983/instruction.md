NPE in Long Line Rule
## Describe the bug
There is NPE in Long Line Rule in `fix` mode for this line

```kotlin
var headerKdoc = firstCodeNode.prevSibling { it.elementType == KDOC } ?: if (firstCodeNode == packageDirectiveNode) importsList?.prevSibling { it.elementType == KDOC } else null
```
## Observed behavior

```kotlin
[ERROR] 2021-07-12 15:56:44 Internal error has occurred in rule [line-length]. Please make an issue on this bug at https://github.com/cqfn/diKTat/.
                       As a workaround you can disable these inspections in yml config: <[LONG_LINE]>.
                       Root cause of the problem is in [D:\IDEAProjects\diKTat\diktat-rules\target\test-classes\test\paragraph3\long_line\LongLineRValueTest.kt] file.
java.lang.NullPointerException
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.fixLongBinaryExpression(LineLength.kt:335)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.fixError(LineLength.kt:267)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.access$fixError(LineLength.kt:63)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength$checkLength$1$1.invoke(LineLength.kt:99)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength$checkLength$1$1.invoke(LineLength.kt:96)
	at org.cqfn.diktat.ruleset.constants.Warnings.warnAndFix(Warnings.kt:260)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.checkLength(LineLength.kt:94)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.logic(LineLength.kt:77)

```

## Steps to Reproduce
It could be reproduced in the diktat demo:
```kotlin
class Example {
    var headerKdoc = firstCodeNode.prevSibling { it.elementType == KDOC } ?: if (firstCodeNode == packageDirectiveNode) importsList?.prevSibling { it.elementType == KDOC } else null
}
```
 or this problematic line can be put in some test, e.g.: LongLineRValueTest.kt

### The NPE appears in both cases, despite the fact that diktat demo and tests uses different values for line limit

## Environment information
* diktat version: 1.0.0-rc.2

### Additional contract requirements

- In fix mode, format the reproduced declaration exactly as follows, breaking immediately after `?:` and using the shown continuation indentation:
```kotlin
    var headerKdoc = firstCodeNode.prevSibling { it.elementType == KDOC } ?:
 if (firstCodeNode == packageDirectiveNode) importsList?.prevSibling { it.elementType == KDOC } else null
```
