6.112.3 broke RuleBasedStateMachine
We get the following error with 6.112.3 and 6.112.4, but no error with 6.112.2: https://github.com/equinor/ert/pull/8891 . It seems like `Bundle`s are not properly unpacked with flatmap as I get `TypeError: cannot unpack non-iterable VarReference object`.

Here is a minimal example:

```python
import hypothesis.strategies as st
from hypothesis.stateful import Bundle, RuleBasedStateMachine, initialize, rule


class StatefulTest(RuleBasedStateMachine):
    buns = Bundle("buns")

    @initialize(target=buns)
    def create_bun(self):
        return 0

    @rule(bun=buns.flatmap(lambda x: st.just(x + 1)))
    def inc(self, bun):
        assert bun


Test = StatefulTest.TestCase
```
ran with `pytest filename.py` it fails with 6.112.4 but passes with 6.112.2.
