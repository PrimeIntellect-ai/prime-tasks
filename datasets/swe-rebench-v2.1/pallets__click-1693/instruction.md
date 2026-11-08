shell completion is case sensitive, even with click.Choice(case_sensitive=False)
### Expected Behavior

Since I set case_sensitive to False, I would expect shell completions to search without case sensitivity.

```python
import click
from click._bashcomplete import get_choices

options = ['Paul', 'Simon', 'Art', 'Garfunkel']

@click.command()
@click.option('--opt', type=click.Choice(options))
def demo():
    pass

completions = list(get_choices(demo, 'dummy', ['--opt'], 'gar'))
assert len(completions) == 1, "expected to find 'Garfunkel' as a completion item"
```

### Actual Behavior

No completions are found. However, if I change the `incomplete` parameter to `"Gar"`, one completion is found as expected.

### Environment

* Python version: 3.7.7
* Click version: 7.0 (but I've reviewed the code on master and it doesn't seem to have a fix)
