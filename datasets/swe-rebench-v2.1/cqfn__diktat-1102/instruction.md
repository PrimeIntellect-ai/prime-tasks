CLASS_SHOULD_NOT_BE_ABSTRACT: abstract fields are ignored
```
abstract class BaseUsesProcessor() {
    // Store uses by file
    abstract val a: String

    fun foo() {}
}
```

is incorrectly treated as NON abstract class
