[BUG] - ParabolicSarIndicator calculates the value incorrectly
I wrote a test for my claim, and then check it with the TradingView site, then found out that ParabolicSarIndicator.getValue works in a wrong way.




```
package org.ta4j.core.indicators;

import org.junit.Test;
import org.ta4j.core.Bar;
import org.ta4j.core.Indicator;
import org.ta4j.core.mocks.MockBar;
import org.ta4j.core.mocks.MockBarSeries;
import org.ta4j.core.num.Num;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;

import static org.junit.Assert.assertEquals;
import static org.ta4j.core.TestUtils.assertNumEquals;

public class ParabolicSarIndicatorTest extends AbstractIndicatorTest<Indicator<Num>, Num> {

    public ParabolicSarIndicatorTest(Function<Number, Num> numFunction) {
        super(numFunction);
    }

    @Test
    public void startUpAndDownTrendTest() {
        List<Bar> bars = new ArrayList<Bar>();
        bars.add(new MockBar(4261.48, 4285.08, 4485.39, 4200.74, numFunction)); // the first candle of BTCUSDT in the Binance cryptocurrency exchange.
        bars.add(new MockBar(4285.08, 4108.37, 4371.52, 3938.77, numFunction)); // the second ...

        ParabolicSarIndicator sar = new ParabolicSarIndicator(new MockBarSeries(bars));

        assertEquals("NaN", sar.getValue(0).toString());
        assertNumEquals(4485.39, sar.getValue(1));
    }

}
```

as shown in the image that I attached, it should be 4485.39, but the value that the indicator calculates is 4371.52

![ParabolicSarIndicatorBug](https://user-images.githubusercontent.com/12148316/99320784-9d4ea000-2881-11eb-8e52-2af32f6d7d89.jpg)

you can check the numbers in https://www.tradingview.com/ with Daily candles on BINANCE:BTCUSDT symbol.
I checked 18 Aug 2017 ParabolicSarIndicator value and it is not equal to what you can see in the image above.

### Additional contract requirements

- For the multi-bar series already represented in the project, `ParabolicSarIndicator.getValue(5)` must be `76.19981196`.
- Given a series of bars specified as `(open, close, high, low)`:
  1. `(4261.48, 4285.08, 4485.39, 4200.74)`
  2. `(4285.08, 4108.37, 4371.52, 3938.77)`
  3. `(4108.37, 4139.98, 4184.69, 3850.00)`
  4. `(4120.98, 4086.29, 4211.08, 4032.62)`
  5. `(4069.13, 4016.00, 4119.62, 3911.79)`
  6. `(4016.00, 4040.00, 4104.82, 3400.00)`
  7. `(4040.00, 4114.01, 4265.80, 4013.89)`
  8. `(4147.00, 4316.01, 4371.68, 4085.01)`
  9. `(4316.01, 4280.68, 4453.91, 4247.48)`
  10. `(4280.71, 4337.44, 4367.00, 4212.41)`

  `ParabolicSarIndicator.getValue(3)` must be `4459.97440000`.
