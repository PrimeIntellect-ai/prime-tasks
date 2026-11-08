Consider making InterledgerAddress.getPrefix non-optional.
Give the `SEGMENTS_UNDERFLOW` logic in the InterledgerAddress preconditions checking, we can likely remove the "optionality" of #getPrefix because there will always be a prefix.

Thus, it's likely that the method contract can instead be this:

```java
default InterledgerAddressPrefix getPrefix() {
    ...
```
