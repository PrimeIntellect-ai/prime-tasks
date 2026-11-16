ast not populated in model
hi,

i have a simple grammar which used to work in 5.6.1 but doesnt work anymore in 5.7.1. the symptom i see is that the models ast is not populated anymore. see the attached example

```
#!/usr/bin/env python3

import tatsu
from tatsu.walkers import NodeWalker

GRAMMAR=r'''
@@grammar::TLA

#
# comment
#
start = expression $;

expression = temporal_expression | nontemporal_top_expression ;
nontemporal_top_expression(SampleExpression) =  expr:nontemporal_expression ;
temporal_expression =    temporal_atom;
temporal_atom(TemporalSeq) = ['Seq'] '(' @:temporal_arg_list ')';
temporal_arg_list = "," .{@+:expression}+;
nontemporal_expression =  number ;

# tokens
number::int = /\d+/;

'''

parser=tatsu.compile(GRAMMAR,asmodel=True)
model = parser.parse('Seq(1,1)')

class PW(NodeWalker):
    def walk_Node(self,node):
        print(f'node {type(node).__name__}')

# i would assume that this walks all nodes but it only walks the top node
PW().walk(model)
# i would assume that node.ast is populated
assert model.ast is not None
```

### Additional contract requirements

- `tatsu.objectmodel.Node` is constructed as `Node(ast=None, **attributes)`. The supplied `ast` value is stored on the instance and exposed as the public attribute `ast`; when omitted it defaults to `None`. Any additional keyword arguments are set as attributes on the instance.
- `tatsu.walkers.DepthFirstWalker.walk(node)` traverses a `Node` by walking its children, and walks a mapping or a sequence element-wise, visiting each contained `Node`.
