Transpiler pass for converting `c_if` to `if_test`
### What should we add?

As developers, we want to transition away from `Instruction.condition` (via the `Instruction{,Set}.c_if` methods) to remove unnecessary state from `Instruction` subclasses.  Part of the backwards compatibility for this support can be a transpiler pass that converts instructions with non-`None` conditions to instances `IfElseBlock`.

This has two main benefits as a temporary measure:
- we will have a path for converting old-style `Instruction` instances within the transpiler, without immediately needing to change the behaviour of `Instruction.c_if`, which is very hard to do within the deprecation policy.
- the dynamic-circuits paths in the IBM provider prefer to have conditionals in this form, in order to more easily apply dynamic decoupling against blocks of instructions.

The first point is the justification for why this is useful to be in Terra (albeit not yet in the preset pass managers - the rest of the support for `IfElseBlock` is too shallow right now), and the second point is why we want this sooner rather than later.

Potential further work: complex conditionals (e.g. `custom_gate.c_if()`) are likely to be expanded by the basis translator into many conditional gates all with the same condition.  Ideally these would be transformed by this pass _before_ basis translation so that they all appear in the same `IfElseBlock`, but right now the support for the control-flow operations in the rest of the transpiler (especially routing) is still being worked on.  One could have a separate classical optimisation pass that runs during optimisation that collects runs of conditionals on the same condition into a single `IfElseBlock`.  This might be moving Terra too far in the direction of classical optimisation, however, and may be better suited for other libraries.

cc: @taalexander.

### Additional contract requirements

The conversion must preserve each conditioned operation and its condition in the resulting if-control-flow block. It must also convert conditioned operations found inside existing nested control-flow blocks. Operations with no legacy condition must remain unchanged.
