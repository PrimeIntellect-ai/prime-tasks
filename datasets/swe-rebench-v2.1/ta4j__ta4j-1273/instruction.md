ProfitLossPercentageCriterion doubts
**I have checked existing issues and wiki**
- [x] I could not find similar [issues](https://github.com/ta4j/ta4j/issues?utf8=%E2%9C%93&q=)
- [x] I could not find a solution in the [wiki](https://ta4j.github.io/ta4j-wiki/) or [faq section](https://ta4j.github.io/ta4j-wiki/FAQ.html)

ProfitLossPercentageCriterion is doing:

![formula](https://latex.codecogs.com/png.image?\bg_white%20ProfitLossPercentageCriterion=\sum_{i=1}^{n}\frac{profit_i}{entryValue_i}\times100)

but percentages are not additive: 12 % + 3 % on 2 positions does not equal 15 % portfolio return.

I think we should be doing instead:

![formula](https://latex.codecogs.com/png.image?\bg_white%20ProfitLossPercentageCriterion=\frac{\sum_{i=1}^{n}profit_i}{\sum_{i=1}^{n}entryValue_i}\times100)

I am not sure if this metric was built to measure something else, that I am missing.

Examples:
| Trade | Cost | Profit | % (profit / cost) |
|-------|------|--------|-------------------|
| 1     | 100  | +10    | +10 % |
| 2     | 100  |  –5    |  –5 % |

Old additive criterion: +10 % + (–5 %) = **+5 %**
Proposed capital weighted: ( +10 – 5 ) / 200 × 100 = **+2.5 %**

| Trade | Cost | Profit | % (profit / cost) |
|-------|------|--------|-------------------|
| 1     | 10   | +1     | +10 % |
| 2     | 1000 | +20    | +2 % |

Old additive criterion: +10 % + 2 % = **+12 %**
Proposed capital weighted: ( +1 + 20 ) / 1010 × 100 ≈ **+2.08 %**
