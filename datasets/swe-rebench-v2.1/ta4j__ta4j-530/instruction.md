NaN generated from Chaikin Oscillator
**I have checked existing issues and wiki**
- [X] I could not find similar [issues](https://github.com/ta4j/ta4j/issues?utf8=%E2%9C%93&q=)
- [X] I could not find a solution in the [wiki](https://ta4j.github.io/ta4j-wiki/) or [faq section](https://ta4j.github.io/ta4j-wiki/FAQ.html)

**Describe the bug**
I found that under certain conditions, the Chaikin Oscillator can start to produce NaN, and once it does, it never recovers.  I tried looking at the code, but got lost in the CachedIndicator class

**To Reproduce**

    private ZoneId timezone = ZoneId.of("Etc/GMT+12");
    @Test
    public void nansGenerated() {
        TimeSeries series = new BaseTimeSeries();
        ZonedDateTime zdt = ZonedDateTime.ofInstant(Instant.ofEpochMilli(1063800000000L), timezone);
        series.addBar(zdt, 17.855, 18.24, 17.68, 18.0, 25282200L);
        zdt = ZonedDateTime.ofInstant(Instant.ofEpochMilli(1063886400000L), timezone);
        series.addBar(zdt, 17.9, 18.915, 17.86, 18.79, 35594400L);
        zdt = ZonedDateTime.ofInstant(Instant.ofEpochMilli(1063972800000L), timezone);
        series.addBar(zdt, 18.79, 18.79, 18.79, 18.79, 23608800L);

        ChaikinOscillatorIndicator indicator = new ChaikinOscillatorIndicator(series);
        for (int i = 0; i < series.getBarCount(); i++) {
            assertThat(indicator.getValue(i)).isNotEqualTo(NaN.NaN);
        }
    }
