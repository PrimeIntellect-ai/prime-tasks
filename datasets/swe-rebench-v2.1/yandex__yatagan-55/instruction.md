`IllegalStateException: Not reached: missing binding` with alias included into parent component
Crash
```
Caused by: java.lang.IllegalStateException: Not reached: missing binding for <...>
        at com.yandex.yatagan.core.graph.impl.BindingGraphImpl.resolveBindingRaw(BindingGraphImpl.kt:142)
        at com.yandex.yatagan.core.graph.impl.BindingGraphImpl.resolveBindingRaw(BindingGraphImpl.kt:141)
        at com.yandex.yatagan.core.graph.impl.BindingGraphImpl$aliasResolveVisitor$1.visitAlias(BindingGraphImpl.kt:131)
        at com.yandex.yatagan.core.graph.impl.BindingGraphImpl$aliasResolveVisitor$1.visitAlias(BindingGraphImpl.kt:130)
        at com.yandex.yatagan.core.graph.impl.bindings.AliasBindingImpl.accept(AliasBindingImpl.kt:74)
        at com.yandex.yatagan.core.graph.impl.BindingGraphImpl.resolveBinding(BindingGraphImpl.kt:136)
        at com.yandex.yatagan.core.graph.impl.TopologicalSortKt.topologicalSort$visit(topologicalSort.kt:55)
        at com.yandex.yatagan.core.graph.impl.TopologicalSortKt.topologicalSort$visit(topologicalSort.kt:55)
        at com.yandex.yatagan.core.graph.impl.TopologicalSortKt.topologicalSort(topologicalSort.kt:68)
        at com.yandex.yatagan.core.graph.impl.bindings.MultiBindingImpl$contributions$2.invoke(MultiBindingImpl.kt:60)
        at com.yandex.yatagan.core.graph.impl.bindings.MultiBindingImpl$contributions$2.invoke(MultiBindingImpl.kt:53)
        at kotlin.SynchronizedLazyImpl.getValue(LazyJVM.kt:74)
        at com.yandex.yatagan.core.graph.impl.bindings.MultiBindingImpl.getContributions(MultiBindingImpl.kt:53)
        at com.yandex.yatagan.core.graph.impl.bindings.MultiBindingImpl.toString(MultiBindingImpl.kt:92)
        at com.yandex.yatagan.core.graph.impl.bindings.MultiBindingImpl.toString(MultiBindingImpl.kt:34)
        at com.yandex.yatagan.validation.impl.ValidationKt.validate(validation.kt:88)
        at com.yandex.yatagan.processor.common.ProcessKt.process(process.kt:59)
        at com.yandex.yatagan.processor.jap.JapYataganProcessor.process(JapYataganProcessor.kt:80)
        at org.jetbrains.kotlin.kapt3.base.incremental.IncrementalProcessor.process(incrementalProcessors.kt:90)
        at org.jetbrains.kotlin.kapt3.base.ProcessorWrapper.process(annotationProcessing.kt:197)
        at jdk.compiler/com.sun.tools.javac.processing.JavacProcessingEnvironment.callProcessor(JavacProcessingEnvironment.java:985)
        ... 42 more
```
The crash occurs when a module with an alias (`@Binds`) is included into a parent component, while the alias' target is materialized in a child component.

### Additional contract requirements

The scenario is exercised by compiling the following Kotlin source (file `test.TestCase`):

```kotlin
import com.yandex.yatagan.*
import javax.inject.*

@Scope annotation class SubScope

interface Api1
interface Api2

@SubScope class Api2Impl @Inject constructor() : Api2
@SubScope class Api1Consumer @Inject constructor(api: Api1)
class Api1Impl @Inject constructor(foo: Api2): Api1

@Module interface MyRootModule {
    @Binds fun api(i: Api1Impl): Api1  // Alias in super
}
@Module interface MySubModule {
    @Binds fun api2(i: Api2Impl): Api2  // Alias in sub

    @Binds @IntoList fun objects1(i: Api1Consumer): Any
    @Binds @IntoList fun objects2(i: Api1Consumer): Any  // add twice
}
@Singleton @Component(modules = [MyRootModule::class])
interface MyRootComponent {
    val sub: MySubComponent
}
@SubScope @Component(isRoot = false, modules = [MySubModule::class])
interface MySubComponent {
    val objects: List<Any>
}
```

Instead of crashing, the compiler must fail the compilation and report exactly the
following diagnostic. The expected output (after the test harness trims and sorts the
messages) is exactly:

```
error: Missing binding for test.Api2
NOTE: No known way to infer the binding
Encountered:
  in graph for root-component test.MyRootComponent
  in graph for component test.MySubComponent
  in entry-point getObjects: java.util.List<java.lang.Object>
                             ^-[*1]--------------------------
  in [1*] list-binding List  { multi-binding-contributor java.lang.Object,  } assembled in graph for component test.MySubComponent
                               ^-[*2]------------------------------------
  in [2*] alias test.MySubModule::objects2(test.Api1Consumer)
                                           ^-[*3]-----------
  in [3*] inject-constructor test.Api1Consumer(test.Api1)
                                               ^-[*4]---
  in [4*] alias test.MyRootModule::api(test.Api1Impl)
                                       ^-[*5]-------
  in [5*] inject-constructor test.Api1Impl(test.Api2)
                                           ^-[*6]---
  here: [6*] <missing>
             ^~~~~~~~~
```
