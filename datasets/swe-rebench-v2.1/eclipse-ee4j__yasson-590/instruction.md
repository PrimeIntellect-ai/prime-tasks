Deserialization of a nested inherited type with an unknown json object fails with a NullPointerException
**Describe the bug**
Deserialization of an inherited type structure fails with a NullPointerException if the structure itself is nested and the structure contains an unknown object which should be skipped.

**To Reproduce**
Very basic model:
```
// base class
@JsonbTypeInfo(key = "_type", value = @JsonbSubtype(type = Derivation.class, alias = "derivationA"))
public class Base {
    private Long id;
}

// derivation of the base class
public class Derivation extends Base {}

// some arbitrary 'outer' root element
public class Outer {
    private Base inner;
}
```

JSON representation containing an unknown object in the nested object.
```
{
  "inner" : {
      "id" : 123,
      "_type" : "derivationA",
      "unmapped" : {}
    }
}
```

If you try to deserialize the given JSON in the given model with `JsonbBuilder.create().fromJson(json, Outer.class);` this exception is thrown
```
jakarta.json.bind.JsonbException: Internal error: null
	at org.eclipse.yasson.internal.DeserializationContextImpl.deserializeItem(DeserializationContextImpl.java:142)
	at org.eclipse.yasson.internal.DeserializationContextImpl.deserialize(DeserializationContextImpl.java:127)
	at org.eclipse.yasson.internal.JsonBinding.deserialize(JsonBinding.java:55)
	at org.eclipse.yasson.internal.JsonBinding.fromJson(JsonBinding.java:62)
	at x.a.b.bla.Bla.bla(Bla.java:52)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:77)
	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.base/java.lang.reflect.Method.invoke(Method.java:568)
	at org.junit.platform.commons.util.ReflectionUtils.invokeMethod(ReflectionUtils.java:727)
	at org.junit.jupiter.engine.execution.MethodInvocation.proceed(MethodInvocation.java:60)
	at org.junit.jupiter.engine.execution.InvocationInterceptorChain$ValidatingInvocation.proceed(InvocationInterceptorChain.java:131)
	at org.junit.jupiter.engine.extension.TimeoutExtension.intercept(TimeoutExtension.java:156)
	at org.junit.jupiter.engine.extension.TimeoutExtension.interceptTestableMethod(TimeoutExtension.java:147)
	at org.junit.jupiter.engine.extension.TimeoutExtension.interceptTestMethod(TimeoutExtension.java:86)
	at org.junit.jupiter.engine.execution.InterceptingExecutableInvoker$ReflectiveInterceptorCall.lambda$ofVoidMethod$0(InterceptingExecutableInvoker.java:103)
	at org.junit.jupiter.engine.execution.InterceptingExecutableInvoker.lambda$invoke$0(InterceptingExecutableInvoker.java:93)
	at org.junit.jupiter.engine.execution.InvocationInterceptorChain$InterceptedInvocation.proceed(InvocationInterceptorChain.java:106)
	at org.junit.jupiter.engine.execution.InvocationInterceptorChain.proceed(InvocationInterceptorChain.java:64)
	at org.junit.jupiter.engine.execution.InvocationInterceptorChain.chainAndInvoke(InvocationInterceptorChain.java:45)
	at org.junit.jupiter.engine.execution.InvocationInterceptorChain.invoke(InvocationInterceptorChain.java:37)
	at org.junit.jupiter.engine.execution.InterceptingExecutableInvoker.invoke(InterceptingExecutableInvoker.java:92)
	at org.junit.jupiter.engine.execution.InterceptingExecutableInvoker.invoke(InterceptingExecutableInvoker.java:86)
	at org.junit.jupiter.engine.descriptor.TestMethodTestDescriptor.lambda$invokeTestMethod$7(TestMethodTestDescriptor.java:217)
	at org.junit.platform.engine.support.hierarchical.ThrowableCollector.execute(ThrowableCollector.java:73)
	at org.junit.jupiter.engine.descriptor.TestMethodTestDescriptor.invokeTestMethod(TestMethodTestDescriptor.java:213)
	at org.junit.jupiter.engine.descriptor.TestMethodTestDescriptor.execute(TestMethodTestDescriptor.java:138)
	at org.junit.jupiter.engine.descriptor.TestMethodTestDescriptor.execute(TestMethodTestDescriptor.java:68)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$6(NodeTestTask.java:151)
	at org.junit.platform.engine.support.hierarchical.ThrowableCollector.execute(ThrowableCollector.java:73)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$8(NodeTestTask.java:141)
	at org.junit.platform.engine.support.hierarchical.Node.around(Node.java:137)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$9(NodeTestTask.java:139)
	at org.junit.platform.engine.support.hierarchical.ThrowableCollector.execute(ThrowableCollector.java:73)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.executeRecursively(NodeTestTask.java:138)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.execute(NodeTestTask.java:95)
	at java.base/java.util.ArrayList.forEach(ArrayList.java:1511)
	at org.junit.platform.engine.support.hierarchical.SameThreadHierarchicalTestExecutorService.invokeAll(SameThreadHierarchicalTestExecutorService.java:41)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$6(NodeTestTask.java:155)
	at org.junit.platform.engine.support.hierarchical.ThrowableCollector.execute(ThrowableCollector.java:73)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$8(NodeTestTask.java:141)
	at org.junit.platform.engine.support.hierarchical.Node.around(Node.java:137)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$9(NodeTestTask.java:139)
	at org.junit.platform.engine.support.hierarchical.ThrowableCollector.execute(ThrowableCollector.java:73)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.executeRecursively(NodeTestTask.java:138)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.execute(NodeTestTask.java:95)
	at java.base/java.util.ArrayList.forEach(ArrayList.java:1511)
	at org.junit.platform.engine.support.hierarchical.SameThreadHierarchicalTestExecutorService.invokeAll(SameThreadHierarchicalTestExecutorService.java:41)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$6(NodeTestTask.java:155)
	at org.junit.platform.engine.support.hierarchical.ThrowableCollector.execute(ThrowableCollector.java:73)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$8(NodeTestTask.java:141)
	at org.junit.platform.engine.support.hierarchical.Node.around(Node.java:137)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.lambda$executeRecursively$9(NodeTestTask.java:139)
	at org.junit.platform.engine.support.hierarchical.ThrowableCollector.execute(ThrowableCollector.java:73)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.executeRecursively(NodeTestTask.java:138)
	at org.junit.platform.engine.support.hierarchical.NodeTestTask.execute(NodeTestTask.java:95)
	at org.junit.platform.engine.support.hierarchical.SameThreadHierarchicalTestExecutorService.submit(SameThreadHierarchicalTestExecutorService.java:35)
	at org.junit.platform.engine.support.hierarchical.HierarchicalTestExecutor.execute(HierarchicalTestExecutor.java:57)
	at org.junit.platform.engine.support.hierarchical.HierarchicalTestEngine.execute(HierarchicalTestEngine.java:54)
	at org.junit.platform.launcher.core.EngineExecutionOrchestrator.execute(EngineExecutionOrchestrator.java:147)
	at org.junit.platform.launcher.core.EngineExecutionOrchestrator.execute(EngineExecutionOrchestrator.java:127)
	at org.junit.platform.launcher.core.EngineExecutionOrchestrator.execute(EngineExecutionOrchestrator.java:90)
	at org.junit.platform.launcher.core.EngineExecutionOrchestrator.lambda$execute$0(EngineExecutionOrchestrator.java:55)
	at org.junit.platform.launcher.core.EngineExecutionOrchestrator.withInterceptedStreams(EngineExecutionOrchestrator.java:102)
	at org.junit.platform.launcher.core.EngineExecutionOrchestrator.execute(EngineExecutionOrchestrator.java:54)
	at org.junit.platform.launcher.core.DefaultLauncher.execute(DefaultLauncher.java:114)
	at org.junit.platform.launcher.core.DefaultLauncher.execute(DefaultLauncher.java:95)
	at org.junit.platform.launcher.core.DefaultLauncherSession$DelegatingLauncher.execute(DefaultLauncherSession.java:91)
	at org.junit.platform.launcher.core.SessionPerRequestLauncher.execute(SessionPerRequestLauncher.java:60)
	at org.eclipse.jdt.internal.junit5.runner.JUnit5TestReference.run(JUnit5TestReference.java:98)
	at org.eclipse.jdt.internal.junit.runner.TestExecution.run(TestExecution.java:40)
	at org.eclipse.jdt.internal.junit.runner.RemoteTestRunner.runTests(RemoteTestRunner.java:529)
	at org.eclipse.jdt.internal.junit.runner.RemoteTestRunner.runTests(RemoteTestRunner.java:756)
	at org.eclipse.jdt.internal.junit.runner.RemoteTestRunner.run(RemoteTestRunner.java:452)
	at org.eclipse.jdt.internal.junit.runner.RemoteTestRunner.main(RemoteTestRunner.java:210)
[HIDDEN]
	at org.eclipse.yasson.internal.deserializer.ObjectDeserializer.deserialize(ObjectDeserializer.java:31)
	at org.eclipse.yasson.internal.deserializer.DefaultObjectInstanceCreator.deserialize(DefaultObjectInstanceCreator.java:57)
	at org.eclipse.yasson.internal.deserializer.DefaultObjectInstanceCreator.deserialize(DefaultObjectInstanceCreator.java:29)
	at org.eclipse.yasson.internal.deserializer.PositionChecker.deserialize(PositionChecker.java:85)
	at org.eclipse.yasson.internal.deserializer.PositionChecker.deserialize(PositionChecker.java:34)
	at org.eclipse.yasson.internal.deserializer.NullCheckDeserializer.deserialize(NullCheckDeserializer.java:46)
	at org.eclipse.yasson.internal.deserializer.NullCheckDeserializer.deserialize(NullCheckDeserializer.java:26)
	at org.eclipse.yasson.internal.deserializer.InheritanceInstanceCreator.deserialize(InheritanceInstanceCreator.java:72)
	at org.eclipse.yasson.internal.deserializer.InheritanceInstanceCreator.deserialize(InheritanceInstanceCreator.java:31)
	at org.eclipse.yasson.internal.deserializer.PositionChecker.deserialize(PositionChecker.java:85)
	at org.eclipse.yasson.internal.deserializer.PositionChecker.deserialize(PositionChecker.java:34)
	at org.eclipse.yasson.internal.deserializer.NullCheckDeserializer.deserialize(NullCheckDeserializer.java:46)
	at org.eclipse.yasson.internal.deserializer.NullCheckDeserializer.deserialize(NullCheckDeserializer.java:26)
	at org.eclipse.yasson.internal.deserializer.ContextSwitcher.deserialize(ContextSwitcher.java:36)
	at org.eclipse.yasson.internal.deserializer.ContextSwitcher.deserialize(ContextSwitcher.java:22)
	at org.eclipse.yasson.internal.deserializer.ObjectDeserializer.deserialize(ObjectDeserializer.java:78)
	at org.eclipse.yasson.internal.deserializer.ObjectDeserializer.deserialize(ObjectDeserializer.java:31)
	at org.eclipse.yasson.internal.deserializer.DefaultObjectInstanceCreator.deserialize(DefaultObjectInstanceCreator.java:57)
	at org.eclipse.yasson.internal.deserializer.DefaultObjectInstanceCreator.deserialize(DefaultObjectInstanceCreator.java:29)
	at org.eclipse.yasson.internal.deserializer.PositionChecker.deserialize(PositionChecker.java:85)
	at org.eclipse.yasson.internal.deserializer.PositionChecker.deserialize(PositionChecker.java:34)
	at org.eclipse.yasson.internal.deserializer.NullCheckDeserializer.deserialize(NullCheckDeserializer.java:46)
	at org.eclipse.yasson.internal.deserializer.NullCheckDeserializer.deserialize(NullCheckDeserializer.java:26)
	at org.eclipse.yasson.internal.DeserializationContextImpl.deserializeItem(DeserializationContextImpl.java:138)
	... 74 more

```

**Expected behavior**
The unmapped object should be skipped, no error should occur.

**System information:**
 - OS: Windows
 - Java Version: 17
 - Yasson Version: 3.0.1
