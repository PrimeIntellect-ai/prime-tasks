Newly implemented Gladstein isn't correct
Woops we should have checked this on @dmanc's #1110. Using `axelrod_fortran` (https://github.com/Axelrod-Python/axelrod-fortran):

```python
>>> import axelrod as axl
>>> import axelrod_fortran as axlf
>>> axl_gladstein = axl.Gladstein()
>>> gladstein = axlf.Player('k76r')
>>> opponent = axl.AntiTitForTat()
>>> axl.Match((axl_gladstein, opponent), turns=5).play()
[(D, C), (C, C), (D, D), (C, C), (C, D)]
>>> axl.Match((gladstein, opponent), turns=5).play()
[(D, C), (C, C), (C, D), (C, D), (D, D)]
```

In the 3rd round the strategy implemented by #1102 is defecting but the fortran strategy (https://github.com/Axelrod-Python/TourExec/blob/master/src/strategies/k76r.f) cooperates.
