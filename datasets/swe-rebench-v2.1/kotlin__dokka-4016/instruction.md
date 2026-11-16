[K2] KMP: `Multiple pages associated with key` reported for an actual class overriding method from java parent
Create a KMP project with JVM + any native target.
```Kotlin
// commonMain
expect class Skiko()

// nativeMain
actual class Skiko actual constructor(){
    fun isShowing(): Boolean {
        return false
    }
}

// jvmMain
file: JavaParent.java
public class JavaParent {
    public boolean isShowing() {
        return true;
    }
}

file: kotlin.kt
actual class Skiko actual constructor(): JavaParent(){
     override fun isShowing(): Boolean {
        return false
    }
}

```

dokkaHtml fails with enabled K2 mode:
```
* Exception is:
org.gradle.api.tasks.TaskExecutionException: Execution failed for task ':module:dokkaHtml'.
	at org.gradle.api.internal.tasks.execution.ExecuteActionsTaskExecuter.lambda$executeIfValid$1(ExecuteActionsTaskExecuter.java:149)
	at org.gradle.internal.Try$Failure.ifSuccessfulOrElse(Try.java:282)
	at org.gradle.api.internal.tasks.execution.ExecuteActionsTaskExecuter.executeIfValid(ExecuteActionsTaskExecuter.java:147)
	at org.gradle.api.internal.tasks.execution.ExecuteActionsTaskExecuter.execute(ExecuteActionsTaskExecuter.java:135)
	at org.gradle.api.internal.tasks.execution.FinalizePropertiesTaskExecuter.execute(FinalizePropertiesTaskExecuter.java:46)
	at org.gradle.api.internal.tasks.execution.ResolveTaskExecutionModeExecuter.execute(ResolveTaskExecutionModeExecuter.java:51)
	at org.gradle.api.internal.tasks.execution.SkipTaskWithNoActionsExecuter.execute(SkipTaskWithNoActionsExecuter.java:57)
	at org.gradle.api.internal.tasks.execution.SkipOnlyIfTaskExecuter.execute(SkipOnlyIfTaskExecuter.java:74)
	at org.gradle.api.internal.tasks.execution.CatchExceptionTaskExecuter.execute(CatchExceptionTaskExecuter.java:36)
	at org.gradle.api.internal.tasks.execution.EventFiringTaskExecuter$1.executeTask(EventFiringTaskExecuter.java:77)
	at org.gradle.api.internal.tasks.execution.EventFiringTaskExecuter$1.call(EventFiringTaskExecuter.java:55)
	at org.gradle.api.internal.tasks.execution.EventFiringTaskExecuter$1.call(EventFiringTaskExecuter.java:52)
	at org.gradle.internal.operations.DefaultBuildOperationRunner$CallableBuildOperationWorker.execute(DefaultBuildOperationRunner.java:204)
	at org.gradle.internal.operations.DefaultBuildOperationRunner$CallableBuildOperationWorker.execute(DefaultBuildOperationRunner.java:199)
	at org.gradle.internal.operations.DefaultBuildOperationRunner$2.execute(DefaultBuildOperationRunner.java:66)
	at org.gradle.internal.operations.DefaultBuildOperationRunner$2.execute(DefaultBuildOperationRunner.java:59)
	at org.gradle.internal.operations.DefaultBuildOperationRunner.execute(DefaultBuildOperationRunner.java:157)
	at org.gradle.internal.operations.DefaultBuildOperationRunner.execute(DefaultBuildOperationRunner.java:59)
	at org.gradle.internal.operations.DefaultBuildOperationRunner.call(DefaultBuildOperationRunner.java:53)
	at org.gradle.internal.operations.DefaultBuildOperationExecutor.call(DefaultBuildOperationExecutor.java:73)
	at org.gradle.api.internal.tasks.execution.EventFiringTaskExecuter.execute(EventFiringTaskExecuter.java:52)
	at org.gradle.execution.plan.LocalTaskNodeExecutor.execute(LocalTaskNodeExecutor.java:42)
	at org.gradle.execution.taskgraph.DefaultTaskExecutionGraph$InvokeNodeExecutorsAction.execute(DefaultTaskExecutionGraph.java:337)
	at org.gradle.execution.taskgraph.DefaultTaskExecutionGraph$InvokeNodeExecutorsAction.execute(DefaultTaskExecutionGraph.java:324)
	at org.gradle.execution.taskgraph.DefaultTaskExecutionGraph$BuildOperationAwareExecutionAction.execute(DefaultTaskExecutionGraph.java:317)
	at org.gradle.execution.taskgraph.DefaultTaskExecutionGraph$BuildOperationAwareExecutionAction.execute(DefaultTaskExecutionGraph.java:303)
	at org.gradle.execution.plan.DefaultPlanExecutor$ExecutorWorker.execute(DefaultPlanExecutor.java:463)
	at org.gradle.execution.plan.DefaultPlanExecutor$ExecutorWorker.run(DefaultPlanExecutor.java:380)
	at org.gradle.internal.concurrent.ExecutorPolicy$CatchAndRecordFailures.onExecute(ExecutorPolicy.java:64)
	at org.gradle.internal.concurrent.AbstractManagedExecutor$1.run(AbstractManagedExecutor.java:47)
Caused by: java.lang.AssertionError: Multiple pages associated with key: /Skiko/isShowing/#/PointingToDeclaration//[DisplaySourceSet(sourceSetIDs=CompositeSourceSetID(children=[:module:dokkaHtml/jvmMain]), name=jvm, platform=jvm)]
	at org.jetbrains.dokka.base.resolvers.local.DokkaLocationProvider.<init>(DokkaLocationProvider.kt:60)
	at org.jetbrains.dokka.base.resolvers.local.DokkaLocationProvider.<init>(DokkaLocationProvider.kt:17)
	at org.jetbrains.dokka.base.resolvers.local.DokkaLocationProviderFactory$getLocationProvider$1.invoke(DokkaLocationProviderFactory.kt:18)
	at org.jetbrains.dokka.base.resolvers.local.DokkaLocationProviderFactory$getLocationProvider$1.invoke(DokkaLocationProviderFactory.kt:17)
	at org.jetbrains.dokka.base.resolvers.local.DokkaLocationProviderFactory$sam$java_util_function_Function$0.apply(DokkaLocationProviderFactory.kt)
	at org.jetbrains.dokka.base.resolvers.local.DokkaLocationProviderFactory.getLocationProvider(DokkaLocationProviderFactory.kt:17)
	at org.jetbrains.dokka.base.renderers.PackageListService.createPackageList(PackageListService.kt:29)
	at org.jetbrains.dokka.base.renderers.PackageListCreator.packageList(preprocessors.kt:29)
	at org.jetbrains.dokka.base.renderers.PackageListCreator.access$packageList(preprocessors.kt:17)
	at org.jetbrains.dokka.base.renderers.PackageListCreator$invoke$1.invoke(preprocessors.kt:24)
	at org.jetbrains.dokka.base.renderers.PackageListCreator$invoke$1.invoke(preprocessors.kt:23)
	at org.jetbrains.dokka.pages.RootPageNode.transformNode(PageNodes.kt:69)
	at org.jetbrains.dokka.pages.RootPageNode.transformNode(PageNodes.kt:70)
	at org.jetbrains.dokka.pages.RootPageNode.transformPageNodeTree(PageNodes.kt:62)
	at org.jetbrains.dokka.base.renderers.PackageListCreator.invoke(preprocessors.kt:23)
	at org.jetbrains.dokka.base.renderers.DefaultRenderer.render(DefaultRenderer.kt:226)
	at org.jetbrains.dokka.base.renderers.html.HtmlRenderer.render(HtmlRenderer.kt:930)
	at org.jetbrains.dokka.base.generation.SingleModuleGeneration.render(SingleModuleGeneration.kt:94)
	at org.jetbrains.dokka.base.generation.SingleModuleGeneration.generate(SingleModuleGeneration.kt:53)
	at org.jetbrains.dokka.DokkaGenerator$generate$1.invoke(DokkaGenerator.kt:34)
	at org.jetbrains.dokka.DokkaGenerator$generate$1.invoke(DokkaGenerator.kt:27)
	at org.jetbrains.dokka.DokkaGeneratorKt.timed(DokkaGenerator.kt:82)
	at org.jetbrains.dokka.DokkaGeneratorKt.access$timed(DokkaGenerator.kt:1)
	at org.jetbrains.dokka.DokkaGenerator.generate(DokkaGenerator.kt:27)
	at org.jetbrains.dokka.DokkaBootstrapImpl.generate(DokkaBootstrapImpl.kt:67)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:77)
	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at org.jetbrains.dokka.gradle.DelegatedInvocationHandler.invoke(automagicTypedProxy.kt:44)
```
For K1 works fine.

**Installation**
- Dokka version: 2.0.0

The project: [Skiko](https://github.com/JetBrains/skiko/blob/master/skiko/src/awtMain/kotlin/org/jetbrains/skiko/SkiaLayer.awt.kt#L199)
