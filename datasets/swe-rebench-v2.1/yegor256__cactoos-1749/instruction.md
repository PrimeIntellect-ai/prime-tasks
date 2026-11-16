missing analog to get substring from the end of the line
Function in commons-lang3 for StringUtils.substring can be called with negative start value to get tail from the string

https://commons.apache.org/proper/commons-lang/apidocs/org/apache/commons/lang3/StringUtils.html#substring-java.lang.String-int-int-

### Additional contract requirements

- A negative end value is also interpreted relative to the end of the string; for example, `new Sub("hello world", -5, -2)` produces `wor`.
