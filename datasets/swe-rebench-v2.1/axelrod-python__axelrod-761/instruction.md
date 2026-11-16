Do we want to skip random sampling for deterministic memory one (and other) strategies?
**EDIT**: This is a long issue but it actually suggests a very minor edit to the `random_choice` function. Thought documenting the long thing was worth it as it's kind of quirky behaviour. :)

Here's a gist (with the code I'm about to write below): https://gist.github.com/drvinceknight/eea3e3e9efd5170fa9f15cdc9cf283a1

Seeding play and creating a `Random` player. Against `p2` and `p3` (two instances of `WinStayLoseShift`) get the same sequences of play for the `Random` player: `['D', 'D', 'C', 'C', 'C']` but against: `p4`(`TitForTat`)  get `['D', 'D', 'C', 'C', 'D']` (different -1'th element).

```
>>> axl.seed(0)
>>> p1 = axl.Random()
>>> p2 = axl.WinStayLoseShift()
>>> match = axl.Match((p1, p2), turns=5)
>>> random_plays_v_p2 = [r[0] for r in match.play()]
>>> random_plays_v_p2
['D', 'D', 'C', 'C', 'C']
>>> axl.seed(0)
>>> p1 = axl.Random()
>>> p3 = axl.WinStayLoseShift()
>>> match = axl.Match((p1, p3), turns=5)
>>> random_plays_v_p2 = [r[0] for r in match.play()]
>>> random_plays_v_p2
['D', 'D', 'C', 'C', 'C']
>>> axl.seed(0)
>>> p1 = axl.Random()
>>> p4 = axl.TitForTat()
>>> match = axl.Match((p1, p4), turns=5)
>>> random_plays_v_p2 = [r[0] for r in match.play()]
>>> random_plays_v_p2
['D', 'D', 'C', 'C', 'D']
```

This is because `WinStayLoseShift` is implemented as a memory one strategy (<https://github.com/Axelrod-Python/Axelrod/blob/master/axelrod/strategies/memoryone.py#L60>). It's a deterministic memory one strategy (the values in the memory-one vector are 0 or 1) but nonetheless it samples a random number (which offsets the random path). As you can see above, seeding is working correctly: `Random` plays the same against `WinStayLoseShift` both times (so there's no issues about reproducibility) so I'm not sure this needs a fix **but**:

[HIDDEN]

```
def random_choice(p=0.5):
    """
    Return 'C' with probability `p`, else return 'D'
    Emulates Python's random.choice(['C', 'D']) since it is not consistent
    across Python 2.7 to Python 3.4"""
    [HIDDEN]

    r = random.random()
    if r < p:
        return Actions.C
    return Actions.D
```

This would have the added benefit of reducing some calls of the random library.

(Tagging @theref as he brought this to my attention.)

### Additional contract requirements

- When `p == 0`, `random_choice` returns `D`; when `p == 1`, it returns `C`. Neither call consumes a random number, so the random state remains unchanged.
