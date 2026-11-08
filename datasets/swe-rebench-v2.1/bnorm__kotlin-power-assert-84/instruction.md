Exclude vararg arrays from expression diagram
Taken from #74:

```text
java.lang.AssertionError: Assertion failed
assert(listOf("a", "b", "c").containsExactlyInAnyOrder("b", "a"))
       |      |              |                         |
       |      |              |                         [Ljava.lang.String;@7579bc7
       |      |              false
       |      [Ljava.lang.String;@34cfd455
       [a, b, c]
```

Also need to handle the spread operator for non-constant arrays. Should all arrays be excluded because they don't have a good `toString()`? Special handling in the diagram builder?

### Additional contract requirements

When an assertion uses a spread operator with a non-constant array operand, the diagram may show the operand's value as usual, but must omit the additional synthetic vararg array created to pass it to the called function.
