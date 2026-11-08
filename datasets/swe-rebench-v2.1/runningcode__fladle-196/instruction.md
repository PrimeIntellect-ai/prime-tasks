`./gradlew flankAuth` throws `TaskExecutionException`
I just setup a project with Fladle and using the User Authentication approach to grant my local machine access to Firebase Test Lab. However, when I tried to run `./gradlew flankAuth`, it keeps throwing `TaskExecutionException`. The workaround I found is to run `./gradlew runFlank` first, then the `flankAuth` will work. Please find the Stacktrace below.

```
* What went wrong:
Execution failed for task ‘:{project}:flankAuth'.
> A problem occurred starting process 'command '/Library/Java/JavaVirtualMachines/jdk1.8.0_231.jdk/Contents/Home/bin/java''

* Try:
Run with --info or --debug option to get more log output. Run with --scan to get full insights.

* Exception is:
org.gradle.api.tasks.TaskExecutionException: Execution failed for task ‘:{project}:flankAuth'.
        at org.gradle.api.internal.tasks.execution.ExecuteActionsTaskExecuter.lambda$executeIfValid$1(ExecuteActionsTaskExecuter.java:207)
        at org.gradle.internal.Try$Failure.ifSuccessfulOrElse(Try.java:263)
        at org.gradle.api.internal.tasks.execution.ExecuteActionsTaskExecuter.executeIfValid(ExecuteActionsTaskExecuter.java:205)
        at org.gradle.api.internal.tasks.execution.ExecuteActionsTaskExecuter.execute(ExecuteActionsTaskExecuter.java:186)
        at org.gradle.api.internal.tasks.execution.CleanupStaleOutputsExecuter.execute(CleanupStaleOutputsExecuter.java:114)
        at org.gradle.api.internal.tasks.execution.FinalizePropertiesTaskExecuter.execute(FinalizePropertiesTaskExecuter.java:46)
        at org.gradle.api.internal.tasks.execution.ResolveTaskExecutionModeExecuter.execute(ResolveTaskExecutionModeExecuter.java:62)
        at org.gradle.api.internal.tasks.execution.SkipTaskWithNoActionsExecuter.execute(SkipTaskWithNoActionsExecuter.java:57)
        at org.gradle.api.internal.tasks.execution.SkipOnlyIfTaskExecuter.execute(SkipOnlyIfTaskExecuter.java:56)
        at org.gradle.api.internal.tasks.execution.CatchExceptionTaskExecuter.execute(CatchExceptionTaskExecuter.java:36)
        at org.gradle.api.internal.tasks.execution.EventFiringTaskExecuter$1.executeTask(EventFiringTaskExecuter.java:77)
        at org.gradle.api.internal.tasks.execution.EventFiringTaskExecuter$1.call(EventFiringTaskExecuter.java:55)
        at org.gradle.api.internal.tasks.execution.EventFiringTaskExecuter$1.call(EventFiringTaskExecuter.java:52)
        at org.gradle.internal.operations.DefaultBuildOperationExecutor$CallableBuildOperationWorker.execute(DefaultBuildOperationExecutor.java:409)
        at org.gradle.internal.operations.DefaultBuildOperationExecutor$CallableBuildOperationWorker.execute(DefaultBuildOperationExecutor.java:399)
        at org.gradle.internal.operations.DefaultBuildOperationExecutor$1.execute(DefaultBuildOperationExecutor.java:157)
        at org.gradle.internal.operations.DefaultBuildOperationExecutor.execute(DefaultBuildOperationExecutor.java:242)
        at org.gradle.internal.operations.DefaultBuildOperationExecutor.execute(DefaultBuildOperationExecutor.java:150)
        at org.gradle.internal.operations.DefaultBuildOperationExecutor.call(DefaultBuildOperationExecutor.java:94)
        at org.gradle.internal.operations.DelegatingBuildOperationExecutor.call(DelegatingBuildOperationExecutor.java:36)
        at org.gradle.api.internal.tasks.execution.EventFiringTaskExecuter.execute(EventFiringTaskExecuter.java:52)
        at org.gradle.execution.plan.LocalTaskNodeExecutor.execute(LocalTaskNodeExecutor.java:41)
        at org.gradle.execution.taskgraph.DefaultTaskExecutionGraph$InvokeNodeExecutorsAction.execute(DefaultTaskExecutionGraph.java:356)
        at org.gradle.execution.taskgraph.DefaultTaskExecutionGraph$InvokeNodeExecutorsAction.execute(DefaultTaskExecutionGraph.java:343)
        at org.gradle.execution.taskgraph.DefaultTaskExecutionGraph$BuildOperationAwareExecutionAction.execute(DefaultTaskExecutionGraph.java:336)
        at org.gradle.execution.taskgraph.DefaultTaskExecutionGraph$BuildOperationAwareExecutionAction.execute(DefaultTaskExecutionGraph.java:322)
        at org.gradle.execution.plan.DefaultPlanExecutor$ExecutorWorker.lambda$run$0(DefaultPlanExecutor.java:127)
        at org.gradle.execution.plan.DefaultPlanExecutor$ExecutorWorker.execute(DefaultPlanExecutor.java:191)
        at org.gradle.execution.plan.DefaultPlanExecutor$ExecutorWorker.executeNextNode(DefaultPlanExecutor.java:182)
        at org.gradle.execution.plan.DefaultPlanExecutor$ExecutorWorker.run(DefaultPlanExecutor.java:124)
        at org.gradle.internal.concurrent.ExecutorPolicy$CatchAndRecordFailures.onExecute(ExecutorPolicy.java:64)
        at org.gradle.internal.concurrent.ManagedExecutorImpl$1.run(ManagedExecutorImpl.java:48)
        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
        at org.gradle.internal.concurrent.ThreadFactoryImpl$ManagedThreadRunnable.run(ThreadFactoryImpl.java:56)
        at java.lang.Thread.run(Thread.java:748)
Caused by: org.gradle.process.internal.ExecException: A problem occurred starting process 'command '/Library/Java/JavaVirtualMachines/jdk1.8.0_231.jdk/Contents/Home/bin/java''
        at org.gradle.process.internal.DefaultExecHandle.execExceptionFor(DefaultExecHandle.java:241)
        at org.gradle.process.internal.DefaultExecHandle.setEndStateInfo(DefaultExecHandle.java:218)
        at org.gradle.process.internal.DefaultExecHandle.failed(DefaultExecHandle.java:372)
        at org.gradle.process.internal.ExecHandleRunner.run(ExecHandleRunner.java:87)
        at org.gradle.internal.operations.CurrentBuildOperationPreservingRunnable.run(CurrentBuildOperationPreservingRunnable.java:42)
        at org.gradle.internal.concurrent.ExecutorPolicy$CatchAndRecordFailures.onExecute(ExecutorPolicy.java:64)
        at org.gradle.internal.concurrent.ManagedExecutorImpl$1.run(ManagedExecutorImpl.java:48)
        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
        at org.gradle.internal.concurrent.ThreadFactoryImpl$ManagedThreadRunnable.run(ThreadFactoryImpl.java:56)
        at java.lang.Thread.run(Thread.java:748)
Caused by: net.rubygrapefruit.platform.NativeException: Could not start '/Library/Java/JavaVirtualMachines/jdk1.8.0_231.jdk/Contents/Home/bin/java'
        at net.rubygrapefruit.platform.internal.DefaultProcessLauncher.start(DefaultProcessLauncher.java:27)
        at net.rubygrapefruit.platform.internal.WrapperProcessLauncher.start(WrapperProcessLauncher.java:36)
        at org.gradle.process.internal.ExecHandleRunner.startProcess(ExecHandleRunner.java:98)
        at org.gradle.process.internal.ExecHandleRunner.run(ExecHandleRunner.java:71)
        ... 7 more
Caused by: java.io.IOException: Cannot run program "/Library/Java/JavaVirtualMachines/jdk1.8.0_231.jdk/Contents/Home/bin/java" (in directory "/Users/{user}/Android/{project}/build/fladle"): error=2, No such file or directory
        at java.lang.ProcessBuilder.start(ProcessBuilder.java:1048)
        at net.rubygrapefruit.platform.internal.DefaultProcessLauncher.start(DefaultProcessLauncher.java:25)
        ... 10 more

```
