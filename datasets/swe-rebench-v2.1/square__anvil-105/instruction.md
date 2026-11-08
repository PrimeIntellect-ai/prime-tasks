Factory generation: nested class with lowercase name
Anvil: 2.0,2

Reproducer:
```
class MyClass @Inject constructor(a: asg) {
  class asg @Inject constructor()
}
```

Exception:
```
e: java.lang.IllegalArgumentException: couldn't make a guess for com.example.myapplication.MyClass.asg
        at com.squareup.kotlinpoet.ClassName$Companion.bestGuess(TypeName.kt:465)
        at com.squareup.anvil.compiler.codegen.KotlinPoetKt.requireTypeName(KotlinPoet.kt:65)
        at com.squareup.anvil.compiler.codegen.KotlinPoetKt.mapToParameter(KotlinPoet.kt:110)
        at com.squareup.anvil.compiler.codegen.dagger.InjectConstructorFactoryGenerator.generateFactoryClass(InjectConstructorFactoryGenerator.kt:63)
```

### Additional contract requirements

For a nested class `MyClass.innerClass` whose constructor is annotated with `@Inject`, a factory class named `MyClass_innerClass_Factory` is generated in the same package as `MyClass`. The generated factory:

- implements `dagger.internal.Factory<MyClass.innerClass>`;
- has a single no-argument constructor;
- exposes a static `create()` method that returns the factory instance, and repeated calls return the same instance;
- exposes a static `newInstance()` method that returns a new instance of `MyClass.innerClass`;
- exposes an instance `get()` method that returns a new instance of `MyClass.innerClass`.
