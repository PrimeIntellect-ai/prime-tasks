Bumping to Quarkus 3.18.x or 3.19.x causes exception of "Couldn't instantiate DependentResource"
For context, i'm currently running Quarkus  3.17.8 and Kotlin 2.0.21. Also using Quarkus Operator SDK (version defined via the Quarkus Platform).

I have a Reconciler with a DependentResource, and that DependentResource has a dependency that is being injected by Quarkus:
```
@ControllerConfiguration(
    dependents = [
        Dependent(
            type = MyDR::class
        )
    ],
)
class UserReconciler(
    private val dep: Dependency,
) : Reconciler<User>
```
```
@KubernetesDependent
@Singleton
class MyDR(
    private val dep: Dependency,
) : CRUDKubernetesDependentResource<RoleBinding, User>(RoleBinding::class.java),
    BulkDependentResource<RoleBinding, User> {

```
 This works and has been working.

Now when upgrading to Quarkus 3.18.x or even 3.19.x (for simplification I'm using 3.19.1), I have done all the needed changes for JOSDK v5 (in the example above, use the [`@Workflow` annotation](https://javaoperatorsdk.io/blog/2025/01/06/version-5-released/#workflow-annotation) to declare a dependent resource for example) and it is failing to start with:


> 2025-03-07 09:15:30,485 ERROR [io.qua.dep.dev.IsolatedDevModeMain] (main) Failed to start quarkus: java.lang.RuntimeException: io.quarkus.builder.BuildException: Build failure: Build failed due to errors
> 	[error]: Build step io.quarkiverse.operatorsdk.deployment.QuarkusControllerConfigurationBuildStep#createControllerConfigurations threw an exception: io.javaoperatorsdk.operator.OperatorException: Couldn't instantiate DependentResource 'org.example.MyDR'.
> 	at io.javaoperatorsdk.operator.api.config.Utils.instantiateAndConfigureIfNeeded(Utils.java:238)
> 	at io.javaoperatorsdk.operator.api.reconciler.dependent.DependentResourceFactory.associatedResourceType(DependentResourceFactory.java:32)
> 	at io.javaoperatorsdk.operator.processing.dependent.kubernetes.KubernetesDependentConverter.createInformerConfig(KubernetesDependentConverter.java:47)
> 	at io.javaoperatorsdk.operator.processing.dependent.kubernetes.KubernetesDependentConverter.configFrom(KubernetesDependentConverter.java:30)
> 	at io.quarkiverse.operatorsdk.deployment.QuarkusControllerConfigurationBuildStep$1.configFrom(QuarkusControllerConfigurationBuildStep.java:68)
> 	at io.javaoperatorsdk.operator.processing.dependent.kubernetes.KubernetesDependentConverter.configFrom(KubernetesDependentConverter.java:12)
> 	at io.javaoperatorsdk.operator.api.config.dependent.DependentResourceConfigurationResolver.configureSpecFromConfigured(DependentResourceConfigurationResolver.java:57)
> 	at io.quarkiverse.operatorsdk.deployment.QuarkusControllerConfigurationBuildStep.createDependentResourceSpec(QuarkusControllerConfigurationBuildStep.java:483)
> 	at io.quarkiverse.operatorsdk.deployment.QuarkusControllerConfigurationBuildStep.lambda$initializeWorkflowIfNeeded$13(QuarkusControllerConfigurationBuildStep.java:317)
> 	at java.base/java.util.LinkedHashMap$LinkedValues.forEach(LinkedHashMap.java:833)
> 	at io.quarkiverse.operatorsdk.deployment.QuarkusControllerConfigurationBuildStep.initializeWorkflowIfNeeded(QuarkusControllerConfigurationBuildStep.java:316)
> 	at io.quarkiverse.operatorsdk.deployment.QuarkusControllerConfigurationBuildStep.createConfiguration(QuarkusControllerConfigurationBuildStep.java:299)
> 	at io.quarkiverse.operatorsdk.deployment.QuarkusControllerConfigurationBuildStep.lambda$createControllerConfigurations$3(QuarkusControllerConfigurationBuildStep.java:121)
> 	at java.base/java.util.stream.ReferencePipeline$3$1.accept(ReferencePipeline.java:197)
> 	at java.base/java.util.HashMap$ValueSpliterator.forEachRemaining(HashMap.java:1787)
> 	at java.base/java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:509)
> 	at java.base/java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:499)
> 	at java.base/java.util.stream.ReduceOps$ReduceOp.evaluateSequential(ReduceOps.java:921)
> 	at java.base/java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)
> 	at java.base/java.util.stream.ReferencePipeline.collect(ReferencePipeline.java:682)
> 	at io.quarkiverse.operatorsdk.deployment.QuarkusControllerConfigurationBuildStep.createControllerConfigurations(QuarkusControllerConfigurationBuildStep.java:132)
> 	at java.base/java.lang.invoke.MethodHandle.invokeWithArguments(MethodHandle.java:733)
> 	at io.quarkus.deployment.ExtensionLoader$3.execute(ExtensionLoader.java:856)
> 	at io.quarkus.builder.BuildContext.run(BuildContext.java:255)
> 	at org.jboss.threads.ContextHandler$1.runWith(ContextHandler.java:18)
> 	at org.jboss.threads.EnhancedQueueExecutor$Task.doRunWith(EnhancedQueueExecutor.java:2675)
> 	at org.jboss.threads.EnhancedQueueExecutor$Task.run(EnhancedQueueExecutor.java:2654)
> 	at org.jboss.threads.EnhancedQueueExecutor.runThreadBody(EnhancedQueueExecutor.java:1627)
> 	at org.jboss.threads.EnhancedQueueExecutor$ThreadBody.run(EnhancedQueueExecutor.java:1594)
> 	at java.base/java.lang.Thread.run(Thread.java:1583)
> 	at org.jboss.threads.JBossThread.run(JBossThread.java:499)
> Caused by: java.lang.IllegalStateException: Couldn't find a no-arg constructor for org.example.MyDR
> 	at io.javaoperatorsdk.operator.api.config.Utils.getConstructor(Utils.java:248)
> 	at io.javaoperatorsdk.operator.api.config.Utils.instantiateAndConfigureIfNeeded(Utils.java:227)
> 	... 30 more
> Caused by: java.lang.NoSuchMethodException: org.example.MyDR.<init>()
> 	at java.base/java.lang.Class.getConstructor0(Class.java:3761)
> 	at java.base/java.lang.Class.getDeclaredConstructor(Class.java:2930)
> 	at io.javaoperatorsdk.operator.api.config.Utils.getConstructor(Utils.java:245)
> 	... 31 more
>

Thanks in advance.
