'Short' incorrectly calculated by ProfitLossCriterion
**I have checked existing issues and wiki**
- [x] I could not find similar [issues](https://github.com/ta4j/ta4j/issues?utf8=%E2%9C%93&q=)
- [x] I could not find a solution in the [wiki](https://ta4j.github.io/ta4j-wiki/) or [faq section](https://ta4j.github.io/ta4j-wiki/FAQ.html)

**Describe the bug**
Criterias analysis is not working correctly for sell orders, for example:

ProfitLossCriterion.class

```
/**
     * Calculates the profit or loss of a sell trade.
     * @param series a time series
     * @param trade a trade
     * @return the profit or loss of the trade
     */
    private Num [HIDDEN](TimeSeries series, Trade trade) {
        Num exitClosePrice = trade.getExit().getPrice().isNaN() ?
                series.getBar(trade.getExit().getIndex()).getClosePrice() : trade.getExit().getPrice();
        Num entryClosePrice = trade.getEntry().getPrice().isNaN() ?
                series.getBar(trade.getEntry().getIndex()).getClosePrice() : trade.getEntry().getPrice();

        [HIDDEN]
    }
```

**To Reproduce**
Run any strategy on SELL order param to have your profits calculated as losses and vice versa

**Expected behavior**
For BUY order it is ok to calculate profit as (exitPrice - entryPrice)*amount, but for short you actually earn when price decrease so  (entryPrice - exitPrice)*amount

**Additional context**
I would be more than happy to see some criterion explanations like if calculation is in amount or price or percentage - hard to verify sometime.
