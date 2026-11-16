ModelBuilderSemantics doesn't include optional attributes
If I have a rule that with an optional named component, that component shows up as `None` when using the AST, but is missing from the model class when using `ModelBuilderSemantics`, see the code below:

```py
import tatsu
from tatsu.model import ModelBuilderSemantics

grammar = r"""
foo::Foo = left:identifier [ ':' right:identifier ] $ ;
identifier = /\w+/ ;
"""

grammar = tatsu.compile(grammar)

a = grammar.parse('foo : bar', semantics=ModelBuilderSemantics())
assert a.left == 'foo'
assert a.right == 'bar'

b = grammar.parse('foo', semantics=ModelBuilderSemantics())
assert b.left == 'foo'
assert b.right is None  # AttributeError: 'Foo' object has no attribute 'right'
```
