Switch the default Kotlin struct style to builderless
Per the readme, Kotlin structs are still generated with `Builder` classes for backwards compatibility.  Since we're bumping from 2.x to 3.x, this is a fine opportunity to give people smaller code by default.

### Additional contract requirements

- Add a public method `withDataClassBuilders()` on `com.microsoft.thrifty.kgen.KotlinCodeGenerator`. It takes no arguments, returns a `KotlinCodeGenerator`, and enables generation of Kotlin structs with inner `Builder` classes.
- Add a public command-line flag `--kt-struct-builders` to the Thrifty compiler that enables generation of Kotlin structs with inner `Builder` classes.
