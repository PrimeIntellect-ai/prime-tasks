Add a reactive strategy class
Any objection to adding a reactive strategy class?

First described here: http://dl.acm.org/citation.cfm?id=64712 it's just a subset of a Memory One strategy where only the action of the opponent is considered.

So where a mem 1 strategy is defined by $(p_1, p_2, p_3, p_4)$ (probabilities of cooperating in states CC, CD, DC, DD), a reactive strategy is a mem 1 strategy with the constraint: $p_1=p_3$ and $p_2=p_4$.

I don't suggest adding anything to the players list (so no defaults that would differ from any other strategy) but just adding the class so that if a user wanted to create a reactive strategy they'd go:

```
>>> import axelrod as axl
>>> p1, p2 = .4, .5
>>> player = axl.ReactivePlayer((p1, p2))
```

As opposed to what can currently be done:

```
>>> import axelrod as axl
>>> p1, p2 = .4, .5
>>> player = axl.MemoryOnePlayer((p1, p2, p1, p2))
```

I suggest that this would be implemented by simple inheritance of the MemoryOnePlayer (so we're not talking about a lot of lines of code here at all).

---

The motivation for this is selfish: it would be handy for students to use in my game theory class where I'm not sure I want to go in to full detail of the Memory One Players but a simple api to create a reactive strategy would be cool.

### Additional contract requirements

- `axelrod.ReactivePlayer` is a public class that accepts a positional pair of
  probabilities, e.g. `axelrod.ReactivePlayer((p1, p2))`.
- The instance's `name` attribute is the string `"Reactive Player: (p1, p2)"`,
  where `p1` and `p2` are the two supplied probabilities (so
  `ReactivePlayer((0, 0)).name` is `"Reactive Player: (0, 0)"`).
- The instance's `classifier['stochastic']` is `True` when any supplied
  probability is strictly between 0 and 1, and `False` when every supplied
  probability is exactly 0 or 1.
- The initial move is `C`.
