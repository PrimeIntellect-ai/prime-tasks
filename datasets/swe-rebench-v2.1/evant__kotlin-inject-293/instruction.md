Compile error in generated code: Unresolved reference: _scoped
Here's a stripped down repro case. Basically I have a cycle, but the `Lazy` avoid its somewhat. kotlin-inject seems to handle this nicely via the generated `lateinit`... but the `run` block surrounding it removes the `require(parent is ScopedComponent)` from inferences (not sure why).

[HIDDEN]

``` kotlin
@Component
@ApplicationScope
abstract class ParentComponent {
    @Provides
    fun provideHttpClient(
        dataRepository: DataRepository
    ): HttpClient = HttpClient(dataRepository)
}

@Component
@ActivityScope
abstract class ChildComponent(
    @Component val parent: ParentComponent
) {
    abstract val dataRepository: DataRepository
}

@ApplicationScope
@Inject
class DataRepository(
    val authRepository: Lazy<Api>,
)

@ApplicationScope
@Inject
class Api(
    val dataRepository: Lazy<DataRepository>,
)

class HttpClient(
    val dataRepository: DataRepository
)
```

This generates:

``` kotlin
public class InjectChildComponent(
  parent: ParentComponent
) : ChildComponent(parent), ScopedComponent {
  public override val _scoped: LazyMap = LazyMap()

  public override val dataRepository: DataRepository
    get() {
      require(parent is ScopedComponent)
      return parent._scoped.get("app.tivi.inject.AuthRepository") {
        run {
          lateinit var dataRepository: DataRepository

          // Chris:
          // parent is no longer inferred as ScopedComponent here,
          // so `parent._scoped` below doesn't compile

          DataRepository(
            authRepository = lazy {
              parent._scoped.get("app.tivi.inject.Api") {
                Api(
                  dataRepository = lazy {
                    parent._scoped.get("app.tivi.inject.AuthRepository") {
                      dataRepository
                    }
                  }
                )
              }
            }
          ).also {
            dataRepository = it
          }
        }

      }
    }
}
```

### Additional contract requirements

- Generated code for the reported Lazy-mediated dependency cycle must compile when it accesses the scoped parent.
- Resolving a scoped dependency cycle through a child component must preserve the same instances across both `Lazy` back-references and the scoped parent.
