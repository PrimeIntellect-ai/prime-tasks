[BUG] ParabolicSarIndicator throws NPE from getValue() method
Hello!
In continuation of #973:
Unfortunately current solution #975 doesn't work as expected. It can be checked by test like this:
```java
    @Test
    public void growingBarSeriesTest() {
        ZonedDateTime now = ZonedDateTime.now();
        List<Bar> bars = new ArrayList<>();
        bars.add(new MockBar(now, 74.5, 75.1, 75.11, 74.06, 0, 0, 0, numFunction));

        MockBarSeries mockBarSeries = new MockBarSeries(bars);
        mockBarSeries.setMaximumBarCount(3);

        mockBarSeries.addBar(new MockBar(now.plusSeconds(1),75.09, 75.9, 76.030000, 74.640000, 0, 0, 0, numFunction));
        mockBarSeries.addBar(new MockBar(now.plusSeconds(2),79.99, 75.24, 76.269900, 75.060000, 0, 0, 0, numFunction));
        mockBarSeries.addBar(new MockBar(now.plusSeconds(3),75.30, 75.17, 75.280000, 74.500000, 0, 0, 0, numFunction));
        mockBarSeries.addBar(new MockBar(now.plusSeconds(4),75.16, 74.6, 75.310000, 74.540000, 0, 0, 0, numFunction));
        mockBarSeries.addBar(new MockBar(now.plusSeconds(5),74.58, 74.1, 75.467000, 74.010000, 0, 0, 0, numFunction));

        ParabolicSarIndicator sar = new ParabolicSarIndicator(mockBarSeries);

        assertEquals(NaN.NaN, sar.getValue(mockBarSeries.getBeginIndex()));
        assertEquals(NaN.NaN, sar.getValue(mockBarSeries.getRemovedBarsCount()));

        assertNotEquals(NaN.NaN, sar.getValue(mockBarSeries.getRemovedBarsCount() + 1));
        assertNotEquals(NaN.NaN, sar.getValue(mockBarSeries.getEndIndex()));
    }
```

This will throws NPE:
```java
java.lang.NullPointerException: Cannot invoke "java.lang.Boolean.booleanValue()" because the return value of "java.util.Map.get(Object)" is null

	at org.ta4j.core.indicators.ParabolicSarIndicator.calculateInternal(ParabolicSarIndicator.java:153)
	at org.ta4j.core.indicators.ParabolicSarIndicator.calculate(ParabolicSarIndicator.java:116)
	at org.ta4j.core.indicators.ParabolicSarIndicator.calculate(ParabolicSarIndicator.java:47)
	at org.ta4j.core.indicators.CachedIndicator.getValue(CachedIndicator.java:126)
	at org.ta4j.core.indicators.RecursiveCachedIndicator.getValue(RecursiveCachedIndicator.java:89)
	at org.ta4j.core.indicators.ParabolicSarIndicatorTest.growingBarSeriesTest(ParabolicSarIndicatorTest.java:71)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:77)
	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.base/java.lang.reflect.Method.invoke(Method.java:568)
	at org.junit.runners.model.FrameworkMethod$1.runReflectiveCall(FrameworkMethod.java:59)
	at org.junit.internal.runners.model.ReflectiveCallable.run(ReflectiveCallable.java:12)
	at org.junit.runners.model.FrameworkMethod.invokeExplosively(FrameworkMethod.java:56)
	at org.junit.internal.runners.statements.InvokeMethod.evaluate(InvokeMethod.java:17)
	at org.junit.runners.ParentRunner$3.evaluate(ParentRunner.java:306)
	at org.junit.runners.BlockJUnit4ClassRunner$1.evaluate(BlockJUnit4ClassRunner.java:100)
	at org.junit.runners.ParentRunner.runLeaf(ParentRunner.java:366)
	at org.junit.runners.BlockJUnit4ClassRunner.runChild(BlockJUnit4ClassRunner.java:103)
	at org.junit.runners.BlockJUnit4ClassRunner.runChild(BlockJUnit4ClassRunner.java:63)
	at org.junit.runners.ParentRunner$4.run(ParentRunner.java:331)
	at org.junit.runners.ParentRunner$1.schedule(ParentRunner.java:79)
	at org.junit.runners.ParentRunner.runChildren(ParentRunner.java:329)
	at org.junit.runners.ParentRunner.access$100(ParentRunner.java:66)
	at org.junit.runners.ParentRunner$2.evaluate(ParentRunner.java:293)
	at org.junit.runners.ParentRunner.run(ParentRunner.java:413)
	at org.junit.runners.Suite.runChild(Suite.java:128)
	at org.junit.runners.Suite.runChild(Suite.java:27)
	at org.junit.runners.ParentRunner$4.run(ParentRunner.java:331)
	at org.junit.runners.ParentRunner$1.schedule(ParentRunner.java:79)
	at org.junit.runners.ParentRunner.runChildren(ParentRunner.java:329)
	at org.junit.runners.ParentRunner.access$100(ParentRunner.java:66)
	at org.junit.runners.ParentRunner$2.evaluate(ParentRunner.java:293)
	at org.junit.runners.ParentRunner$3.evaluate(ParentRunner.java:306)
	at org.junit.runners.ParentRunner.run(ParentRunner.java:413)
	at org.junit.runner.JUnitCore.run(JUnitCore.java:137)
	at com.intellij.junit4.JUnit4IdeaTestRunner.startRunnerWithArgs(JUnit4IdeaTestRunner.java:69)
	at com.intellij.rt.junit.IdeaTestRunner$Repeater$1.execute(IdeaTestRunner.java:38)
	at com.intellij.rt.execution.junit.TestsRepeater.repeat(TestsRepeater.java:11)
	at com.intellij.rt.junit.IdeaTestRunner$Repeater.startRunnerWithArgs(IdeaTestRunner.java:35)
	at com.intellij.rt.junit.JUnitStarter.prepareStreamsAndStart(JUnitStarter.java:232)
	at com.intellij.rt.junit.JUnitStarter.main(JUnitStarter.java:55)
```

I guess we should reconsider the algorithm of [CachedIndicator](https://github.com/ta4j/ta4j/blob/master/ta4j-core/src/main/java/org/ta4j/core/indicators/CachedIndicator.java) before trying to fix [ParabolicSarIndicator](https://github.com/ta4j/ta4j/blob/master/ta4j-core/src/main/java/org/ta4j/core/indicators/ParabolicSarIndicator.java).

### Additional contract requirements

- `BarSeries.getBeginIndex()` returns the index of the first valid bar of the series. For a bar series with a maximum bar count, once the oldest bars are removed to keep the series within the maximum, the begin index advances to the index of the oldest retained bar, i.e. it equals the number of removed bars. For example, a series that has had 6 bars added with a maximum bar count of 3 has a begin index of 3.
- `BarSeries.getSubSeries(startIndex, endIndex)` returns a sub-series containing the bars with absolute series indices from `startIndex` (inclusive) to `endIndex` (exclusive). The indices are absolute, i.e. they count bars that have already been removed, so the returned sub-series contains `endIndex - startIndex` bars.
