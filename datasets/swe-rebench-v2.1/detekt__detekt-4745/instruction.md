`VarCouldBeVal` reported on `private lateinit var`
<!-- The bug you're experiencing might have already be reported! -->
<!-- Please search in the [issues](https://github.com/detekt/detekt/issues) before creating one. -->

## Steps to Reproduce
```kt
class A {
    private lateinit var label: JLabel
}
```

## Context
Per https://github.com/detekt/detekt/pull/4664#issuecomment-1086835405, I'm not sure our use-case is mainstream enough to warrant a change in detekt, but I'd like to bring it up as a datapoint anyways in case there there is additional discussion in the future.

As part of my work I develop plugins for JetBrains IDEs.
We have a number of older Kotlin source files backing visual forms designed using the JetBrains [GUI Designer](https://www.jetbrains.com/help/idea/gui-designer.html). I'm fuzzy on all the details, but how this generally works is that there's instrumentation at compile time that injects constructors and all the necessary method calls needed to setup the Swing components correctly.

For example, the code snippet above would result in decompiled bytecode that might look like the following:
```kt
class A {
    private lateinit var label: JLabel

    private fun `$$$setupUI$$$`() {
        label = JLabel("some label text")
        label.setIcon(Icon("and maybe we have a /path/to/icon declared here too"))
    }

    init {
        `$$$setupUI$$$`()
    }
}
```

Obviously since detekt acts on source code and not bytecode, it can't know that the fields actually end up initialized.

The `VarCouldBeVal` rule is still very useful for us, so as a workaround to this regression we'd likely either mark the ~60 or so instances in our codebase with an annotation or throw it in a baseline file and call it a day.

## Your Environment
* Version of detekt used: 1.20.0
* Link to your project (if it's a public repository): https://github.com/aws/aws-toolkit-jetbrains

### Additional contract requirements

`VarCouldBeVal` must support the `ignoreLateinitVar` configuration option. When enabled, it must not report `lateinit` variables, and it must continue to report eligible non-`lateinit` variables.
