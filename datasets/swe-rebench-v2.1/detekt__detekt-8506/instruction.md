`UnusedImports` false negative with two imports of the same name from different packages
<!-- The bug you're experiencing might have already be reported! -->
<!-- Please search in the [issues](https://github.com/detekt/detekt/issues) before creating one. -->

## Expected Behavior
<!-- Tell us what should happen -->
`UnusedImports` error on `import kotlin.io.path.Path`. intellij's unused import inspection is able to detect it:

![Image](https://github.com/user-attachments/assets/9e39e596-944f-4d75-b98b-7717bb5a7bd1)

## Observed Behavior
no error

## Steps to Reproduce
<!-- Provide a link to a live example, or an unambiguous set of steps to -->
<!-- reproduce this bug. Include code to reproduce, if relevant -->
```kt
import java.nio.file.Path // this import is used
import kotlin.io.path.Path // this one is not

typealias Foo = Path
```
## Context
<!-- How has this issue affected you? What are you trying to accomplish? -->
<!-- Providing context helps us come up with a solution that is most useful in the real world -->

## Your Environment
<!-- Include as many relevant details about the environment you experienced the bug in -->
* Version of detekt used: 1.23.8
* Operating System and version: windows 10
