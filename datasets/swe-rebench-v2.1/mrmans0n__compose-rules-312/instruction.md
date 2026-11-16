Error on multiple pieces of content error when you have an early return
Not sure if this is just bad code design or if the rule should handle this. This was passing fine on 0.4.5 but failed when I upgraded to 0.4.8

Example Composable:

```
@Composable
fun EarlyReturnComposable(isVisible: Boolean, modifier: Modifier = Modifier) {
    if (!isVisible) {
        Text("Shouldn't be visible")
        return
    }

    Text("Should be visible")
}
```

Result:

> Composable functions should only be emitting content into the composition from one source at their top level.
>
> See https://mrmans0n.github.io/compose-rules/rules/#do-not-emit-multiple-pieces-of-content for more information. (cannot be auto-corrected)
