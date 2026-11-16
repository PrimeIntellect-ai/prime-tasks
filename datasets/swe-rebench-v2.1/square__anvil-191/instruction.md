False positive check leads to compilation fail
First of all thanks for quick support for dagger's AssistedInject!

We did a migration to it with `2.0.12-SNAPSHOT` anvil version and everything worked fine, but with update to stable 2.0.12 compilation started failing with `@Provides methods cannot be abstract` error.

Module failed to compile looks like this:
```
@Module
@ContributesTo(AppComponent::class)
interface Module {

    @Binds
    @Singleton
    fun bindsDependency(i: DependencyImpl): Dependency

    companion object {
        @Provides
        @Singleton
        fun providesDepB(depA: DepA): DepB = DepB(depA)
    }
}
```
This code is valid with both dagger kapt and anvil 2.0.11.

It looks like it was introduced in #186  https://github.com/square/anvil/pull/186/files#diff-c59935dc466bb8ab8c74b8e866de744af48eeddaa9340add1833bb09776ff354R63
[HIDDEN]

### Additional contract requirements

- A `@Provides` method declared inside a companion object of an interface is valid and must not produce the error `@Provides methods cannot be abstract`.
- An abstract `@Provides` method must produce the error `@Provides methods cannot be abstract`.
- A `@Provides` method declared directly in an interface, outside of its companion object, must produce the error `@Provides methods cannot be abstract`.
