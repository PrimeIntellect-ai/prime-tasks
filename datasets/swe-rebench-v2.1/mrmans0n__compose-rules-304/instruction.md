`compose:naming-check` is not honored in subclasses
**Describe the bug**

Code sample:

```kt
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

sealed interface Screen {

  @Suppress("ktlint:compose:naming-check")
  @Composable
  fun content(modifier: Modifier)

  data object Main : Screen {
    @Composable
    override fun content(modifier: Modifier) {}
  }
}
```

run ktlint check:

```sh
Step 'ktlint' found problem in 'src/main/java/Screen.kt':
Error on line: 12, column: 18
rule: compose:naming-check
Composable functions that return Unit should start with an uppercase letter.
They are considered declarative entities that can be either present or absent in a composition and therefore follow the naming rules for classes.
```

**Expected behavior**

No warning thrown like in AS

<img width="1071" alt="image" src="https://github.com/twitter/compose-rules/assets/10363352/cc739631-3744-4009-8b55-39ac132b324e">
