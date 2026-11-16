Connot find symbol exception for properties provided in a dagger module in a seperate gradle module
In gradle module A:
``` kotlin
class Foo
@Module class MyModule {
    @get:Provides val foo = Foo()
}
```
In gradle module B which depends on A:
``` kotlin
@Component(modules = [MyModule::class]) interface MyComponent {
    fun foo(): Foo
}
```
```
build/generated/source/kapt/debug/com/package/package/DaggerMyComponent.java:5: error: cannot find symbol
import com.package.package.MyModule_GetFooFactory;
                          ^

### Additional contract requirements

For a property declared with `@get:Provides` in a Dagger module, a factory class is generated in the module's package. The class is named `<ModuleClassName>_Get<PropertyName>Factory` for a property in a regular module and `<ModuleClassName>_Companion_Get<PropertyName>Factory` for a property in a companion object; for example, a property `string` in `DaggerModule1` produces `DaggerModule1_GetStringFactory`.

The generated factory class provides:
- A constructor taking the module instance for a regular (non-object) module, and no parameters for an `object` or companion-object module.
- A static `create` method taking the module instance and returning a new factory instance for a regular module, and taking no parameters and returning the singleton factory instance for an `object` or companion-object module.
- A static getter named `get<PropertyName>` (for example `getString`) taking the module instance for a regular module and no parameters for an `object` or companion-object module, and returning the property value. For a non-nullable property the getter throws when the value is null; for a nullable property it returns the value, which may be null.
- An implementation of `dagger.internal.Factory<T>` whose `get()` method returns the property value, which may be null for a nullable property.
