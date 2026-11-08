[BUG] ExpectancyCriterion Incorrect Calculation
**I have checked existing issues and wiki**
- [X] I could not find similar [issues](https://github.com/ta4j/ta4j/issues?utf8=%E2%9C%93&q=)
- [X] I could not find a solution in the [wiki](https://ta4j.github.io/ta4j-wiki/) or [faq section](https://ta4j.github.io/ta4j-wiki/FAQ.html)

**Describe the bug**
The Expectancy calculation is incorrect. In it's current form, it can only ever be negative or zero.

**To Reproduce**
Steps to reproduce the behavior:
1. Run ExpectancyCriterionTest.calculateOnlyWithProfitPositions(). The trading record has 100% win rate with positive overall profit yet the expectancy score is 0.

**Expected behavior**
In the above unit test the expectancy should be 1.0

**Additional context**
The expectancy formula linked in the comments (https://www.straightforex.com/advanced-forex-course/money-management/two-important-things-to-be-considered/) is incorrect, which is likely the root cause of this bug.

### Additional contract requirements

- For each of the mixed-profit-and-loss records covered by `ExpectancyCriterionTest`, the expectancy should be 0.25.
