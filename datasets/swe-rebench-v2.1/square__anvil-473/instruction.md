NoSuchElementException on resolving star imports

Kotlin: 1.6.10
Anvil: 2.3.10-1-6-0

Reproduce:
`a/A.java`
```java
package a;

public class A {

   public abstract static class AA {
   }
}
```

`b/B.kt`
```kotlin
package b

import a.A
import a.A.*//this import breaks compilation

class B : A.AA()
```




Exception:
```
java.util.NoSuchElementException: Collection contains no element matching the predicate.
	at com.squareup.anvil.compiler.internal.PsiUtilsKt.requireFqName(PsiUtils.kt:943)
	at com.squareup.anvil.compiler.internal.PsiUtilsKt.requireFqName(PsiUtils.kt:341)
	at com.squareup.anvil.compiler.internal.PsiUtilsKt.fqNameOrNull(PsiUtils.kt:270)
	at com.squareup.anvil.compiler.internal.PsiUtilsKt$allPsiSuperClasses$superOrNull$1.invoke(PsiUtils.kt:255)
	at com.squareup.anvil.compiler.internal.PsiUtilsKt$allPsiSuperClasses$superOrNull$1.invoke(PsiUtils.kt:255)
	at kotlin.sequences.TransformingSequence$iterator$1.next(Sequences.kt:210)
	at kotlin.sequences.FilteringSequence$iterator$1.calcNext(Sequences.kt:170)
	at kotlin.sequences.FilteringSequence$iterator$1.hasNext(Sequences.kt:194)
	at kotlin.sequences.TransformingSequence$iterator$1.hasNext(Sequences.kt:214)
	at kotlin.sequences.FilteringSequence$iterator$1.calcNext(Sequences.kt:169)
	at kotlin.sequences.FilteringSequence$iterator$1.hasNext(Sequences.kt:194)
	at com.squareup.anvil.compiler.internal.PsiUtilsKt.allPsiSuperClasses(PsiUtils.kt:916)
	at com.squareup.anvil.compiler.codegen.dagger.MembersInjectionUtilsKt.memberInjectParameters(MembersInjectionUtils.kt:83)
	at com.squareup.anvil.compiler.codegen.dagger.MembersInjectorGenerator.generateCodePrivate(MembersInjectorGenerator.kt:49)
	at com.squareup.anvil.compiler.codegen.PrivateCodeGenerator.generateCode(PrivateCodeGenerator.kt:21)
	at com.squareup.anvil.compiler.codegen.CodeGenerationExtension.analysisCompleted$generateCode(CodeGenerationExtension.kt:93)
	at com.squareup.anvil.compiler.codegen.CodeGenerationExtension.analysisCompleted(CodeGenerationExtension.kt:114)
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
	at org.jetbrains.kotlin.incremental.IncrementalJvmCompilerRunner.runCompiler(IncrementalJvmCompilerRunner.kt:434)
	at org.jetbrains.kotlin.incremental.IncrementalJvmCompilerRunner.runCompiler(IncrementalJvmCompilerRunner.kt:120)
	at org.jetbrains.kotlin.incremental.IncrementalCompilerRunner.compileIncrementally(IncrementalCompilerRunner.kt:357)
	at org.jetbrains.kotlin.incremental.IncrementalCompilerRunner.compileIncrementally$default(IncrementalCompilerRunner.kt:299)
	at org.jetbrains.kotlin.incremental.IncrementalCompilerRunner.compileImpl(IncrementalCompilerRunner.kt:159)
	at org.jetbrains.kotlin.incremental.IncrementalCompilerRunner.compile(IncrementalCompilerRunner.kt:80)
	at org.jetbrains.kotlin.daemon.CompileServiceImplBase.execIncrementalCompiler(CompileServiceImpl.kt:622)
	at org.jetbrains.kotlin.daemon.CompileServiceImplBase.access$execIncrementalCompiler(CompileServiceImpl.kt:100)
	at org.jetbrains.kotlin.daemon.CompileServiceImpl.compile(CompileServiceImpl.kt:1713)
	at jdk.internal.reflect.GeneratedMethodAccessor104.invoke(Unknown Source)
	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.base/java.lang.reflect.Method.invoke(Method.java:566)
	at java.rmi/sun.rmi.server.UnicastServerRef.dispatch(UnicastServerRef.java:359)
	at java.rmi/sun.rmi.transport.Transport$1.run(Transport.java:200)
	at java.rmi/sun.rmi.transport.Transport$1.run(Transport.java:197)
	at java.base/java.security.AccessController.doPrivileged(Native Method)
	at java.rmi/sun.rmi.transport.Transport.serviceCall(Transport.java:196)
	at java.rmi/sun.rmi.transport.tcp.TCPTransport.handleMessages(TCPTransport.java:562)
	at java.rmi/sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.run0(TCPTransport.java:796)
	at java.rmi/sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.lambda$run$0(TCPTransport.java:677)
	at java.base/java.security.AccessController.doPrivileged(Native Method)
	at java.rmi/sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.run(TCPTransport.java:676)
	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
	at java.base/java.lang.Thread.run(Thread.java:834)



```
