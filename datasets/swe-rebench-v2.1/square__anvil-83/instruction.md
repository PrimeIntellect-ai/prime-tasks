Factory generation: lowercase class names
```
class myclass @Inject constructor()
```

This simple reproducer fails inside your codegen with exception.
```
at com.squareup.kotlinpoet.ClassName$Companion.bestGuess(TypeName.kt:459)
        at com.squareup.anvil.compiler.codegen.dagger.KotlinPoetKt.asClassName(KotlinPoet.kt:37)
        at com.squareup.anvil.compiler.codegen.dagger.InjectConstructorFactoryGenerator.generateFactoryClass(InjectConstructorFactoryGenerator.kt:55)
```
