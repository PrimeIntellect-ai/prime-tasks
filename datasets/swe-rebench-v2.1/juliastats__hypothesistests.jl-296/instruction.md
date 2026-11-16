Lower and upper limits of CI for proportion
Should lower limit be `min(0, val)` and upper `max(val, 1)`?

for example:
```
confint(HypothesisTests.BinomialTest(0, 5), method = :agresti_coull)
```

Result
```
(**-**0.05457239484968546, 0.4890548596328611)
```

### Additional contract requirements

- For a proportion confidence interval, the lower limit must be at least 0 and the upper limit must be at most 1.
