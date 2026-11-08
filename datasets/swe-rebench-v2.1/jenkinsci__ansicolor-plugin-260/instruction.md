Support JDK 17
### What feature do you want to see added?

Tests currently fail on JDK 17.

```
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home

[INFO] Running InjectedTest
[ERROR] Tests run: 2, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 11.794 s <<< FAILURE! - in InjectedTest
[ERROR] org.jvnet.hudson.test.junit.FailedTest.org.jvnet.hudson.test.JellyTestSuiteBuilder$JellyTestSuite  Time elapsed: 0.008 s  <<< ERROR!
org.jvnet.hudson.reactor.ReactorException: com.google.common.util.concurrent.ExecutionError: java.lang.NoClassDefFoundError: Could not initialize class com.google.inject.internal.cglib.core.$ReflectUtils
	at org.jvnet.hudson.reactor.Reactor.execute(Reactor.java:282)
	at jenkins.InitReactorRunner.run(InitReactorRunner.java:49)
	at jenkins.model.Jenkins.executeReactor(Jenkins.java:1162)
	at jenkins.model.Jenkins.<init>(Jenkins.java:960)
	at hudson.model.Hudson.<init>(Hudson.java:86)
	at org.jvnet.hudson.test.HudsonTestCase.newHudson(HudsonTestCase.java:514)
	at org.jvnet.hudson.test.HudsonTestCase.setUp(HudsonTestCase.java:342)
	at org.jvnet.hudson.test.JellyTestSuiteBuilder$JellyTestSuite.setUp(JellyTestSuiteBuilder.java:130)
	at org.jvnet.hudson.test.junit.GroupedTest.run(GroupedTest.java:49)
	at junit.framework.TestSuite.runTest(TestSuite.java:241)
	at junit.framework.TestSuite.run(TestSuite.java:236)
	at org.junit.internal.runners.JUnit38ClassRunner.run(JUnit38ClassRunner.java:90)
	at org.apache.maven.surefire.junit4.JUnit4Provider.execute(JUnit4Provider.java:377)
	at org.apache.maven.surefire.junit4.JUnit4Provider.executeWithRerun(JUnit4Provider.java:284)
	at org.apache.maven.surefire.junit4.JUnit4Provider.executeTestSet(JUnit4Provider.java:248)
	at org.apache.maven.surefire.junit4.JUnit4Provider.invoke(JUnit4Provider.java:167)
	at org.apache.maven.surefire.booter.ForkedBooter.runSuitesInProcess(ForkedBooter.java:456)
	at org.apache.maven.surefire.booter.ForkedBooter.execute(ForkedBooter.java:169)
	at org.apache.maven.surefire.booter.ForkedBooter.run(ForkedBooter.java:595)
	at org.apache.maven.surefire.booter.ForkedBooter.main(ForkedBooter.java:581)
Caused by: com.google.common.util.concurrent.ExecutionError: java.lang.NoClassDefFoundError: Could not initialize class com.google.inject.internal.cglib.core.$ReflectUtils
	at com.google.common.cache.LocalCache$Segment.get(LocalCache.java:2232)
	at com.google.common.cache.LocalCache.get(LocalCache.java:3965)
	at com.google.common.cache.LocalCache.getOrLoad(LocalCache.java:3969)
	at com.google.common.cache.LocalCache$LocalManualCache.get(LocalCache.java:4829)
	at com.google.common.cache.LocalCache$LocalManualCache.getUnchecked(LocalCache.java:4834)
	at com.google.inject.internal.FailableCache.get(FailableCache.java:48)
	at com.google.inject.internal.ConstructorInjectorStore.get(ConstructorInjectorStore.java:50)
	at com.google.inject.internal.ConstructorBindingImpl.initialize(ConstructorBindingImpl.java:136)
	at com.google.inject.internal.InjectorImpl.initializeBinding(InjectorImpl.java:533)
	at com.google.inject.internal.AbstractBindingProcessor$Processor$1.run(AbstractBindingProcessor.java:160)
	at com.google.inject.internal.ProcessedBindingData.initializeBindings(ProcessedBindingData.java:44)
	at com.google.inject.internal.InternalInjectorCreator.initializeStatically(InternalInjectorCreator.java:123)
	at com.google.inject.internal.InternalInjectorCreator.build(InternalInjectorCreator.java:107)
	at com.google.inject.Guice.createInjector(Guice.java:96)
	at com.google.inject.Guice.createInjector(Guice.java:73)
	at com.google.inject.Guice.createInjector(Guice.java:62)
	at hudson.ExtensionFinder$GuiceFinder.<init>(ExtensionFinder.java:289)
	at java.base/jdk.internal.reflect.NativeConstructorAccessorImpl.newInstance0(Native Method)
	at java.base/jdk.internal.reflect.NativeConstructorAccessorImpl.newInstance(NativeConstructorAccessorImpl.java:77)
	at java.base/jdk.internal.reflect.DelegatingConstructorAccessorImpl.newInstance(DelegatingConstructorAccessorImpl.java:45)
	at java.base/java.lang.reflect.Constructor.newInstanceWithCaller(Constructor.java:499)
	at java.base/java.lang.reflect.ReflectAccess.newInstance(ReflectAccess.java:128)
	at java.base/jdk.internal.reflect.ReflectionFactory.newInstance(ReflectionFactory.java:347)
	at java.base/java.lang.Class.newInstance(Class.java:645)
	at net.java.sezpoz.IndexItem.instance(IndexItem.java:181)
	at hudson.ExtensionFinder$Sezpoz._find(ExtensionFinder.java:701)
	at hudson.ExtensionFinder$Sezpoz.find(ExtensionFinder.java:687)
	at hudson.ClassicPluginStrategy.findComponents(ClassicPluginStrategy.java:348)
	at hudson.ExtensionList.load(ExtensionList.java:380)
	at hudson.ExtensionList.ensureLoaded(ExtensionList.java:316)
	at hudson.ExtensionList.getComponents(ExtensionList.java:182)
	at jenkins.model.Jenkins$6.onInitMilestoneAttained(Jenkins.java:1159)
	at jenkins.InitReactorRunner$1.onAttained(InitReactorRunner.java:88)
	at org.jvnet.hudson.reactor.ReactorListener$Aggregator.lambda$onAttained$3(ReactorListener.java:102)
	at org.jvnet.hudson.reactor.ReactorListener$Aggregator.run(ReactorListener.java:109)
	at org.jvnet.hudson.reactor.ReactorListener$Aggregator.onAttained(ReactorListener.java:102)
	at org.jvnet.hudson.reactor.Reactor$1.run(Reactor.java:177)
	at org.jvnet.hudson.reactor.Reactor$Node.run(Reactor.java:117)
	at jenkins.security.ImpersonatingExecutorService$1.run(ImpersonatingExecutorService.java:68)
	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1136)
	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:635)
	at java.base/java.lang.Thread.run(Thread.java:833)
Caused by: java.lang.NoClassDefFoundError: Could not initialize class com.google.inject.internal.cglib.core.$ReflectUtils
	at com.google.inject.internal.cglib.reflect.$FastClassEmitter.<init>(FastClassEmitter.java:67)
	at com.google.inject.internal.cglib.reflect.$FastClass$Generator.generateClass(FastClass.java:72)
	at com.google.inject.internal.cglib.core.$DefaultGeneratorStrategy.generate(DefaultGeneratorStrategy.java:25)
	at com.google.inject.internal.cglib.core.$AbstractClassGenerator.create(AbstractClassGenerator.java:216)
	at com.google.inject.internal.cglib.reflect.$FastClass$Generator.create(FastClass.java:64)
	at com.google.inject.internal.BytecodeGen.newFastClass(BytecodeGen.java:204)
	at com.google.inject.internal.DefaultConstructionProxyFactory.create(DefaultConstructionProxyFactory.java:54)
	at com.google.inject.internal.ProxyFactory.create(ProxyFactory.java:159)
	at com.google.inject.internal.ConstructorInjectorStore.createConstructor(ConstructorInjectorStore.java:90)
	at com.google.inject.internal.ConstructorInjectorStore.access$000(ConstructorInjectorStore.java:29)
	at com.google.inject.internal.ConstructorInjectorStore$1.create(ConstructorInjectorStore.java:37)
	at com.google.inject.internal.ConstructorInjectorStore$1.create(ConstructorInjectorStore.java:33)
	at com.google.inject.internal.FailableCache$1.load(FailableCache.java:37)
	at com.google.common.cache.LocalCache$LoadingValueReference.loadFuture(LocalCache.java:3568)
	at com.google.common.cache.LocalCache$Segment.loadSync(LocalCache.java:2350)
	at com.google.common.cache.LocalCache$Segment.lockedGetOrLoad(LocalCache.java:2313)
	at com.google.common.cache.LocalCache$Segment.get(LocalCache.java:2228)
	... 41 more
```

### Upstream changes

_No response_
