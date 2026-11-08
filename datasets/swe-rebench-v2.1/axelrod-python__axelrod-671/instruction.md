Error in payoff_diffs_means?
I think there's a bug for self interactions for the payoff_diffs_means (this only affects stochastic strategies):

```
>>> import axelrod as axl
>>> from numpy import mean
>>> axl.seed(0)
>>> players = [s() for s in axl.demo_strategies]
>>> tournament = axl.Tournament(players, repetitions=2, turns=5)
>>> results = tournament.play()
>>> results.score_diffs
[[[0.0, 0.0],
  [-5.0, -5.0],
  [0.0, 0.0],
  [0.0, 0.0],
  [-3.0, -1.9999999999999998]],
 [[5.0, 5.0], [0.0, 0.0], [1.0, 1.0], [1.0, 1.0], [1.0, 1.0]],
 [[0.0, 0.0], [-1.0, -1.0], [0.0, 0.0], [0.0, 0.0], [0.0, -1.0]],
 [[0.0, 0.0], [-1.0, -1.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]],
 [[3.0, 1.9999999999999998], [-1.0, -1.0], [0.0, 1.0], [0.0, 0.0], [2.0, 0.0]]]
```

If you look at the last element we see that over the two repetitions, the Random strategy scored 2 and 0 against itself (both positive numbers).

```
>>> results.payoff_diffs_means
[[0.0, -5.0, 0.0, 0.0, -2.5],
 [5.0, 0.0, 1.0, 1.0, 1.0],
 [0.0, -1.0, 0.0, 0.0, -0.5],
 [0.0, -1.0, 0.0, 0.0, 0.0],
 [2.5, -1.0, 0.5, 0.0, -1.0]]
```

That last mean is `-1.0` which is just the opposite mean (this is due to how the self interactions are handled and the fact that `build_payoff_diffs_means` rebuilds the payoff diff means from the interactions. A more direct calculation gives:

```
>>> [HIDDEN]
[[0.0, -5.0, 0.0, 0.0, -2.5],
 [5.0, 0.0, 1.0, 1.0, 1.0],
 [0.0, -1.0, 0.0, 0.0, -0.5],
 [0.0, -1.0, 0.0, 0.0, 0.0],
 [2.5, -1.0, 0.5, 0.0, 1.0]]
```

which is the expected result. [HIDDEN]

### Additional contract requirements

- `payoff_diffs_means` must report the mean of each player's score differences against each opponent across repetitions, including for self-interactions.
