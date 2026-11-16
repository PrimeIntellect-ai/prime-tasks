False positive RedundantSuspendModifier when invoking a suspending function parameter
```kotlin
interface ApiCallStateModel : ViceSource<ApiCallState>, State<ApiCallState> {
  @Composable
  override fun currentState(): ApiCallState = value

  fun reset()
}

abstract class AbstractApiCallStateModel(
  private val context: Context,
) : ApiCallStateModel {
  final override var value: ApiCallState by mutableStateOf(ApiCallState.Pending)
    private set

  protected suspend fun <T> awaitApiCallResult(
    call: suspend () -> MyResult<T>,
  ): MyResult<T> {
    value = ApiCallState.InFlight

    val result = call()
    value = when(result) {
      is MyResult.Error -> ApiCallState.Error(
        error = result.message ?: "error",
      )

      is MyResult.Success -> ApiCallState.Pending
    }

    return result
  }

  override fun reset() {
    value = ApiCallState.Pending
  }
}
```

## Your Environment
* Version of detekt used: 2.0.0-alpha.0
* Version of Gradle used (if applicable): 9.0.0
