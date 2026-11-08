Multiple stateful @preconditions cause all but one to be silently ignored
While investigating an initialize/invariant fix for #2860, I noticed that unlike most of the other decorators, `@precondition` has no check preventing multiple preconditions for the same method.

Unfortunately, this doesn't result in the intuitive outcome of multiple preconditions being and-ed together. Instead, they each silently overwrite each other, with only the outermost precondition prevailing.

```python

def test_multiple_precondition_bug():
    class MultiplePreconditionMachine(RuleBasedStateMachine):
        @rule(x=integers())
        def good_method(self, x):
            pass

        @precondition(lambda self: True)
        @precondition(lambda self: False)
        @rule(x=integers())
        def bad_method_a(self, x):
            """This rule unexpectedly runs, even though it shouldn't."""
            assert False

        @precondition(lambda self: False)
        @precondition(lambda self: True)
        @rule(x=integers())
        def bad_method_b(self, x):
            """This rule never runs, but for the wrong reason."""
            assert False

    run_state_machine_as_test(MultiplePreconditionMachine)

```

```
Falsifying example:
state = MultiplePreconditionMachine()
state.bad_method_a(x=0)
state.teardown()
```
