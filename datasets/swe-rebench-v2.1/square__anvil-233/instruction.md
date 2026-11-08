Anvil 2.2.0 fails when using `PublishedApi` targeting a class
After updating to version 2.2.0 I started to face the following error (stacktrace at the bottom): `e: com.squareup.anvil.compiler.AnvilCompilationException: Back-end (JVM) Internal error: com.<REDACTED>.WeakReferenceDelegate is contributed to the Dagger graph, but the module is not public. Only public modules are supported. File being compiled: (25,16) in /Users/marcellogalhardo/Developer/<REDACTED>/WeakReferenceDelegate.kt`

However, the intriguing part is that the `WeakReferenceDelegate` does not contribute to Anvil nor is used in our codebase, it was lost in a legacy module and we do have usages of it in our codebase.

After investigating, I discovered that the problem is a `@PublishedApi` in a `internal class`. To reproduce, add the following class to any project using Anvil 2.2.0:

```kotlin
@PublishedApi
internal class FailAnvil
```

It looks like Anvil is messing with any `@PublishedApi` that targets a `class`, and validating if the target `class` is `public` before doing the "multibinding contributions" - which will consistently fail the build.

Note that this problem is not a blocker for me as I can simple delete the class to fix it but might impact other people. The problem does not happen at version 2.1.0 or below.

## Stacktrace

```
e: com.squareup.anvil.compiler.AnvilCompilationException: Back-end (JVM) Internal error: com.<REDACTED>.WeakReferenceDelegate is contributed to the Dagger graph, but the module is not public. Only public modules are supported.
File being compiled: (25,16) in /Users/marcellogalhardo/Developer/<REDACTED>/WeakReferenceDelegate.kt

	at com.squareup.anvil.compiler.codegen.ContributesToGenerator$generateCode$3.invoke(ContributesToGenerator.kt:50)
	at com.squareup.anvil.compiler.codegen.ContributesToGenerator$generateCode$3.invoke(ContributesToGenerator.kt:30)
	at kotlin.sequences.SequencesKt___SequencesKt$onEach$1.invoke(_Sequences.kt:1944)
	at kotlin.sequences.TransformingSequence$iterator$1.next(Sequences.kt:210)
	at kotlin.sequences.TransformingSequence$iterator$1.next(Sequences.kt:210)
	at kotlin.sequences.SequencesKt___SequencesKt.toCollection(_Sequences.kt:752)
	at kotlin.sequences.SequencesKt___SequencesKt.toMutableList(_Sequences.kt:782)
	at kotlin.sequences.SequencesKt___SequencesKt.toList(_Sequences.kt:773)
	at com.squareup.anvil.compiler.codegen.ContributesToGenerator.generateCode(ContributesToGenerator.kt:97)
	at com.squareup.anvil.compiler.codegen.CodeGenerationExtension$analysisCompleted$2.invoke(CodeGenerationExtension.kt:57)
	at com.squareup.anvil.compiler.codegen.CodeGenerationExtension.analysisCompleted(CodeGenerationExtension.kt:62)
	at org.jetbrains.kotlin.cli.jvm.compiler.TopDownAnalyzerFacadeForJVM.analyzeFilesWithJavaIntegration$invokeExtensionsOnAnalysisComplete(TopDownAnalyzerFacadeForJVM.kt:108)
	at org.jetbrains.kotlin.cli.jvm.compiler.TopDownAnalyzerFacadeForJVM.analyzeFilesWithJavaIntegration(TopDownAnalyzerFacadeForJVM.kt:118)
	at org.jetbrains.kotlin.cli.jvm.compiler.TopDownAnalyzerFacadeForJVM.analyzeFilesWithJavaIntegration$default(TopDownAnalyzerFacadeForJVM.kt:85)
	at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler$analyze$1.invoke(KotlinToJVMBytecodeCompiler.kt:517)
	at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler$analyze$1.invoke(KotlinToJVMBytecodeCompiler.kt:508)
	at org.jetbrains.kotlin.cli.common.messages.AnalyzerWithCompilerReport.analyzeAndReport(AnalyzerWithCompilerReport.kt:114)
	at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler.analyze(KotlinToJVMBytecodeCompiler.kt:508)
	at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler.compileModules$cli(KotlinToJVMBytecodeCompiler.kt:188)
	at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler.compileModules$cli$default(KotlinToJVMBytecodeCompiler.kt:154)
	at org.jetbrains.kotlin.cli.jvm.K2JVMCompiler.doExecute(K2JVMCompiler.kt:169)
	at org.jetbrains.kotlin.cli.jvm.K2JVMCompiler.doExecute(K2JVMCompiler.kt:52)
	at org.jetbrains.kotlin.cli.common.CLICompiler.execImpl(CLICompiler.kt:88)
	at org.jetbrains.kotlin.cli.common.CLICompiler.execImpl(CLICompiler.kt:44)
	at org.jetbrains.kotlin.cli.common.CLITool.exec(CLITool.kt:98)
	at org.jetbrains.kotlin.incremental.IncrementalJvmCompilerRunner.runCompiler(IncrementalJvmCompilerRunner.kt:386)
	at org.jetbrains.kotlin.incremental.IncrementalJvmCompilerRunner.runCompiler(IncrementalJvmCompilerRunner.kt:110)
	at org.jetbrains.kotlin.incremental.IncrementalCompilerRunner.compileIncrementally(IncrementalCompilerRunner.kt:286)
	at org.jetbrains.kotlin.incremental.IncrementalCompilerRunner.compileImpl(IncrementalCompilerRunner.kt:111)
	at org.jetbrains.kotlin.incremental.IncrementalCompilerRunner.compile(IncrementalCompilerRunner.kt:74)
	at org.jetbrains.kotlin.daemon.CompileServiceImplBase.execIncrementalCompiler(CompileServiceImpl.kt:607)
	at org.jetbrains.kotlin.daemon.CompileServiceImplBase.access$execIncrementalCompiler(CompileServiceImpl.kt:96)
	at org.jetbrains.kotlin.daemon.CompileServiceImpl.compile(CompileServiceImpl.kt:1659)
	at sun.reflect.GeneratedMethodAccessor100.invoke(Unknown Source)
	at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.lang.reflect.Method.invoke(Method.java:498)
	at sun.rmi.server.UnicastServerRef.dispatch(UnicastServerRef.java:357)
	at sun.rmi.transport.Transport$1.run(Transport.java:200)
	at sun.rmi.transport.Transport$1.run(Transport.java:197)
	at java.security.AccessController.doPrivileged(Native Method)
	at sun.rmi.transport.Transport.serviceCall(Transport.java:196)
	at sun.rmi.transport.tcp.TCPTransport.handleMessages(TCPTransport.java:573)
	at sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.run0(TCPTransport.java:834)
	at sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.lambda$run$0(TCPTransport.java:688)
	at java.security.AccessController.doPrivileged(Native Method)
	at sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.run(TCPTransport.java:687)
	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
	at java.lang.Thread.run(Thread.java:748)
```
