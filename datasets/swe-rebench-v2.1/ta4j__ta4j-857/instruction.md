[BUG] bar aggregator produce incorrect result when exist a gaps in the serie
**I have checked existing issues and wiki**
- [X] I could not find similar [issues](https://github.com/ta4j/ta4j/issues?utf8=%E2%9C%93&q=)
- [X] I could not find a solution in the [wiki](https://ta4j.github.io/ta4j-wiki/) or [faq section](https://ta4j.github.io/ta4j-wiki/FAQ.html)

**Describe the bug**
aggregator produce incorrect result when exist a gaps

**To Reproduce**
```
        val begin = ZonedDateTime.now()
        val serie = (new BaseBarSeries)
        serie.addBar(Duration.ofMinutes(1), begin.plusMinutes(1), 1, 1, 1, 2, 1)
        serie.addBar(Duration.ofMinutes(1), begin.plusMinutes(2), 2, 1, 1, 3, 1)
        serie.addBar(
          Duration.ofMinutes(1),
          begin.plusMinutes(60),
          1,
          1,
          1,
          1,
          1
        )
        import org.ta4j.core.aggregator._
        val res = new BaseBarSeriesAggregator(
          new DurationBarAggregator(Duration.ofMinutes(2), false)
        ).aggregate(serie, "")
        println(res.getBarData().asScala.mkString)
// {end time: 2021-09-22T21:50:54.267+02:00[Europe/Paris], close price: 3.000000, open price: 1.000000, low price: 1.000000, high price: 1.000000, volume: 2.000000}{end time: 2021-09-22T22:49:54.267+02:00[Europe/Paris], close price: 1.000000, open price: 1.000000, low price: 1.000000, high price: 1.000000, volume: 1.000000}

        val res2 = new BaseBarSeriesAggregator(
          new DurationBarAggregator(Duration.ofMinutes(4), false)
        ).aggregate(serie, "")
        println(res2.getBarData().asScala.mkString)
//{end time: 2021-09-22T21:52:54.267+02:00[Europe/Paris], close price: 1.000000, open price: 1.000000, low price: 1.000000, high price: 1.000000, volume: 3.000000}
```
**Expected behavior**
The aggragator should produce 2 bar with Duration.ofMinutes(2) and Duration.ofMinutes(4). Because 3th bar in serie begin after 60 minutes
