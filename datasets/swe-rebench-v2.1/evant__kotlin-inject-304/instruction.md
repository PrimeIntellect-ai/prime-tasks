Cannot apply scope: @ActivityScope to type with @Assisted parameters
KSP throws this issue
```
e: [ksp] Cannot apply scope: @ActivityScope to type with @Assisted parameters:
 [navigator: com.slack.circuit.runtime.Navigator]
```
This happens only in the new update 0.6.2.

Code:

```
@Inject
class Presenter(
    @Assisted private val navigator: Navigator
) : Presenter<Example> {
    @Composable
    override fun present(): State {}
}
```
```
@Inject
class PresenterFactory(
    private val presenter: (Navigator) -> Presenter,
) : Presenter.Factory {
    override fun create(
        screen: Screen,
        navigator: Navigator,
        context: CircuitContext
    ): Presenter<*>? = when (screen) {
        is HomeScreen -> presenter(navigator)
        else -> null
    }

}

```

### Additional contract requirements

A scoped component can resolve an otherwise unscoped injected class whose constructor has `@Assisted` parameters. The component's scope must not be treated as the class's own scope.
