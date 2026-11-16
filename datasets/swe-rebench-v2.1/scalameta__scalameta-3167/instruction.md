Allow removeOptionalBraces for test cases with Scala 3.3.0 Version
With the new Scala 3.3.0 version, we can now replace
```
test ("………") {
}
```
with
```
test ("……….") :
```
The complier is happy.
However, Scala fmt sbt plugin is not happy with it. Does anyone know how to add the such rule for tests in `.scalafmt.conf` file? It’s not to format the test codes automatically to that style, it’s to allow such change by human.

### Additional contract requirements

A fewer-braces method body is written as a colon at the end of a line followed by an indented block. When such a colon is not followed by an indented block, the source must be rejected as invalid, and parsing must fail with the diagnostic message `expected fewer-braces method body`.
