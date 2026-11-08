False positive UnnamedParameterUse when invoking a lambda
```kotlin
class OnboardingPhoneNumberNavigator(
  private val onNavigateToRequestPin: (String, String) -> Unit,
) {
  fun navigateToRequestPin(
    country: Country,
    phoneNumber: String,
  ) {
    onNavigateToRequestPin(country.code, phoneNumber)
  }
}
```

## Your Environment
* Version of detekt used: 2.0.0-alpha.0
* Version of Gradle used (if applicable): 9.0.0
