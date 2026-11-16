WRONG_NAME_OF_VARIABLE_INSIDE_ACCESSOR false positive trigger
## Describe the bug
See e.g. the following code:
```
val String.blaBla: String
    get() = "bla".blaBla("bla")

fun String.blaBla(string: String): String = this + string
```

WRONG_NAME_OF_VARIABLE_INSIDE_ACCESSOR is triggered, saying that `field` keyword should be used instead of property name inside property accessors. But it seems that it mistakes the `blaBla` method name for the property name because they are the same in this case.

## Expected behavior
WRONG_NAME_OF_VARIABLE_INSIDE_ACCESSOR shouldn't be triggered when there's a method with the same name as the property

## Observed behavior
WRONG_NAME_OF_VARIABLE_INSIDE_ACCESSOR is triggered when there's a method with the same name as the property

## Steps to Reproduce
1. Create an extension variable;
2. Call a method, the name of which is the same as the property itself, within the property getter;
3. Run `diktatCheck` to observe the supposed false positive trigger of WRONG_NAME_OF_VARIABLE_INSIDE_ACCESSOR.

## Environment information
* diktat version: 0.6.2
* build tool (maven/gradle): Gradle 6.7
* how is diktat run (CLI, plugin, etc.): gradle plugin
* kotlin version: 1.5.10
* operating system: Windows 10
* link to a project (if your project is public):
