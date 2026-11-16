Correctly handle `in` and `!in` infix operators
For something like the following:

```kotlin
assert("Hello" in "World")
```

Version `0.12.1` currently throws an exception where version `0.12.0` did not.

```
java.lang.StringIndexOutOfBoundsException: String index out of range: 19
	at java.base/java.lang.StringLatin1.charAt(StringLatin1.java:47)
	at java.base/java.lang.String.charAt(String.java:693)
	at com.bnorm.power.diagram.IrDiagramKt.memberAccessOffset(IrDiagram.kt:198)
	at com.bnorm.power.diagram.IrDiagramKt.findDisplayOffset(IrDiagram.kt:164)
	at com.bnorm.power.diagram.IrDiagramKt.toValueDisplay(IrDiagram.kt:112)
	at com.bnorm.power.diagram.IrDiagramKt.irDiagramString(IrDiagram.kt:46)
```

### Additional contract requirements

- For a failing `assert("Name" in listOf("Hello", "World"))`, the diagnostic must be exactly:

```
Assertion failed
assert("Name" in listOf("Hello", "World"))
              |  |
              |  [Hello, World]
              false
```
