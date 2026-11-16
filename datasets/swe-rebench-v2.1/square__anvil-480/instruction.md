Unable to generate contributed subcomponent with factory
I've got another one when generating a `@ContributesSubcomponent` with a `ParentComponent` inside.

```

@ContributesSubcomponent(
  scope = TrainingScope::class,
  parentScope = Singleton::class
)
public interface NavEntryTrainingScopeComponent {
  @ContributesSubcomponent.Factory
  public interface Factory {
    public fun create(): NavEntryTrainingScopeComponent
  }

  @ContributesTo(Singleton::class)
  public interface ParentComponent {
    public fun getNavEntryTrainingScopeComponent(): Factory
  }
}
```

Error:

```
e: com.squareup.anvil.compiler.api.AnvilCompilationException: Back-end (JVM) Internal error: Couldn't find return type for com.freeletics.app.NavEntryTrainingScopeComponent.ParentComponent.getNavEntryTrainingScopeComponent.
File is unknown

        at com.squareup.anvil.compiler.internal.FunctionReferenceKt.returnType(FunctionReference.kt:90)
        at com.squareup.anvil.compiler.codegen.ContributesSubcomponentHandlerGenerator.findParentComponentInterface(ContributesSubcomponentHandlerGenerator.kt:363)
        at com.squareup.anvil.compiler.codegen.ContributesSubcomponentHandlerGenerator.generateParentComponent(ContributesSubcomponentHandlerGenerator.kt:296)
        at com.squareup.anvil.compiler.codegen.ContributesSubcomponentHandlerGenerator.access$generateParentComponent(ContributesSubcomponentHandlerGenerator.kt:89)
        at com.squareup.anvil.compiler.codegen.ContributesSubcomponentHandlerGenerator$generateCode$6$content$1.invoke(ContributesSubcomponentHandlerGenerator.kt:232)
        at com.squareup.anvil.compiler.codegen.ContributesSubcomponentHandlerGenerator$generateCode$6$content$1.invoke(ContributesSubcomponentHandlerGenerator.kt:197)
        at com.squareup.anvil.compiler.internal.KotlinPoetUtilsKt.buildFile(KotlinPoetUtils.kt:374)
        at com.squareup.anvil.compiler.internal.KotlinPoetUtilsKt.buildFile$default(KotlinPoetUtils.kt:363)
        at com.squareup.anvil.compiler.codegen.ContributesSubcomponentHandlerGenerator.generateCode(ContributesSubcomponentHandlerGenerator.kt:197)
        at com.squareup.anvil.compiler.codegen.CodeGenerationExtension.analysisCompleted$generateCode(CodeGenerationExtension.kt:96)
        at com.squareup.anvil.compiler.codegen.CodeGenerationExtension.analysisCompleted(CodeGenerationExtension.kt:136)
        at org.jetbrains.kotlin.cli.jvm.compiler.TopDownAnalyzerFacadeForJVM$analyzeFilesWithJavaIntegration$2.invoke(TopDownAnalyzerFacadeForJVM.kt:112)
        at org.jetbrains.kotlin.cli.jvm.compiler.TopDownAnalyzerFacadeForJVM.analyzeFilesWithJavaIntegration(TopDownAnalyzerFacadeForJVM.kt:122)
        at org.jetbrains.kotlin.cli.jvm.compiler.TopDownAnalyzerFacadeForJVM.analyzeFilesWithJavaIntegration$default(TopDownAnalyzerFacadeForJVM.kt:96)
        at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler$analyze$1.invoke(KotlinToJVMBytecodeCompiler.kt:262)
        at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler$analyze$1.invoke(KotlinToJVMBytecodeCompiler.kt:53)
        at org.jetbrains.kotlin.cli.common.messages.AnalyzerWithCompilerReport.analyzeAndReport(AnalyzerWithCompilerReport.kt:113)
        at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler.analyze(KotlinToJVMBytecodeCompiler.kt:253)
        at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler.compileModules$cli(KotlinToJVMBytecodeCompiler.kt:100)
        at org.jetbrains.kotlin.cli.jvm.compiler.KotlinToJVMBytecodeCompiler.compileModules$cli$default(KotlinToJVMBytecodeCompiler.kt:58)
        at org.jetbrains.kotlin.cli.jvm.K2JVMCompiler.doExecute(K2JVMCompiler.kt:170)
        at org.jetbrains.kotlin.cli.jvm.K2JVMCompiler.doExecute(K2JVMCompiler.kt:52)
        at org.jetbrains.kotlin.cli.common.CLICompiler.execImpl(CLICompiler.kt:92)
        at org.jetbrains.kotlin.cli.common.CLICompiler.execImpl(CLICompiler.kt:44)
        at org.jetbrains.kotlin.cli.common.CLITool.exec(CLITool.kt:98)
        at org.jetbrains.kotlin.daemon.CompileServiceImpl.compile(CompileServiceImpl.kt:1618)
        at jdk.internal.reflect.GeneratedMethodAccessor108.invoke(Unknown Source)
        at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
        at java.base/java.lang.reflect.Method.invoke(Method.java:568)
        at java.rmi/sun.rmi.server.UnicastServerRef.dispatch(UnicastServerRef.java:360)
        at java.rmi/sun.rmi.transport.Transport$1.run(Transport.java:200)
        at java.rmi/sun.rmi.transport.Transport$1.run(Transport.java:197)
        at java.base/java.security.AccessController.doPrivileged(AccessController.java:712)
        at java.rmi/sun.rmi.transport.Transport.serviceCall(Transport.java:196)
        at java.rmi/sun.rmi.transport.tcp.TCPTransport.handleMessages(TCPTransport.java:587)
        at java.rmi/sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.run0(TCPTransport.java:828)
        at java.rmi/sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.lambda$run$0(TCPTransport.java:705)
        at java.base/java.security.AccessController.doPrivileged(AccessController.java:399)
        at java.rmi/sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.run(TCPTransport.java:704)
        at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1136)
        at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:635)
        at java.base/java.lang.Thread.run(Thread.java:833)
```

Let me know if I should move this to a separate issue.

Update: this one works when I generate `ParentComponent` as a top level class in the same file, but it looks like Anvil also generates a `ParentComponent` in that case.

_Originally posted by @gabrielittner in https://github.com/square/anvil/issues/477#issuecomment-1025167831_
