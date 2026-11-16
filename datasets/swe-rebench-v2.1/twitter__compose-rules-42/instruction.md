Allow @Preview functions to not take Modifier arguments
In general, `detekt.ModifierMissing` is for sure the right approach. Where it gets a little less useful though is on `@Preview` methods. In general, at least in my projects, these are rarely (if ever) used from inside another `@Composable`.

Is there an appetite for a PR adjusting this rule to not match against methods that are also annotated with `@Preview`?

For instance, I'd suggest that `ModifierMissing` not be flagged against this method:

```kotlin
@Composable
@Preview(name = "Container with Single Product", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(name = "Container with Single Product", uiMode = Configuration.UI_MODE_NIGHT_YES)
fun OverviewWithSwitcherContainerWithSingleProductPreview() {
 //
}
```
