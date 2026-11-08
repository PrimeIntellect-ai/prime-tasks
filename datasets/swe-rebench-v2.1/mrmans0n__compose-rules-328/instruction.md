Incorrect compose:lambda-param-in-effect rule failure
This code fails because of the same named ViewModel.onClick() function.

```kotlin
@Composable
fun MyComposable(onClick: () -> Unit, viewModel: MyViewModel = viewModel()) {
    val latestOnClick by rememberUpdatedState(onClick)
    LaunchedEffect(Unit) {
        latestOnClick()
        viewModel.onClick()
    }
    // ...
}
```
