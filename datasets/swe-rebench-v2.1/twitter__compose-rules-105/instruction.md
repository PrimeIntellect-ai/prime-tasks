Feature Request: Allow specifying an optional pattern for `ComposableNaming`
**Is your feature request related to a problem? Please describe.**
In our architecture we can define presenter functions that return State objects. These tend to be define similarly to how [Molecule](https://github.com/cashapp/molecule) does it, where the function acts as business logic. This fails the naming check however.

```kotlin
@Composable
fun ProfilePresenter(
  userFlow: Flow<User>,
  balanceFlow: Flow<Long>,
): ProfileModel {
  val user by userFlow.collectAsState(null)
  val balance by balanceFlow.collectAsState(0L)

  return if (user == null) {
    Loading
  } else {
    Data(user.name, balance)
  }
}
```

**Describe the solution you'd like**
It would be convenient if we could have a matcher config to ignore these types.

```yml
TwitterCompose:
  ComposableNaming:
    active: false
    functionNameExcludes: ['**Presenter']
```

**Describe alternatives you've considered**
The only option right now is to suppress or disable the rule entirely.

**Additional context**
Happy to send a PR if you're open to it 👍

### Additional contract requirements

- Callers can configure a list of regular expressions for composable function names that are exempt from the naming violation "composables that return results should be lowercase" (reported for a composable that returns a value and whose name starts with an uppercase letter).
- Detekt: the exempting patterns are set with the `allowedComposableFunctionNames` property (a list of regex strings) in the configuration of the composable naming rule. For example, `.*Presenter` exempts `ProfilePresenter`.
- ktlint: the exempting patterns are set with the EditorConfig property `twitter_compose_allowed_composable_function_names`, whose value is a comma-separated list of regex strings. For example, `.*Presenter` exempts `ProfilePresenter`.
- A composable whose name matches a configured pattern is not reported with that violation. A composable that returns a value, starts with an uppercase letter, and whose name matches none of the configured patterns is still reported.
