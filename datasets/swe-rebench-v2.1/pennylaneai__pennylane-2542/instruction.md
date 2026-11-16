[BUG] Derivatives of `qml.CommutingEvolution`
In cleaning warnings from the test suite, I found this warning:

```
templates/test_subroutines/test_commuting_evolution.py::TestGradients::test_differentiable_hamiltonian
  /Users/christina/Prog/pl/lib/python3.8/site-packages/autograd/tracer.py:14: UserWarning: Output seems independent of input.
    warnings.warn("Output seems independent of input.")
```

The effect of `CommutingEvolution` on the state did not change with the time.
This problems seems to stem from [HIDDEN]
[HIDDEN]

Upon fixing that bug, we now find that parameter shift no longer works for `CommutingEvolution`.

These two tests start to fail:
```
==================================================================================== short test summary info ====================================================================================
FAILED templates/test_subroutines/test_commuting_evolution.py::TestGradients::test_two_term_case - assert False
FAILED templates/test_subroutines/test_commuting_evolution.py::TestGradients::test_four_term_case - assert False
```

The tests that fail manually specify the frequencies. If the frequencies are specified, the operation sets its own `grad_recipe`.  This `grad_recipe` gives incorrect results.  I have yet to track down the problem with the `grad_recipe` property.


In summary, fixing the bug in the creation of the `ApproxTimeEvolution` operation allows finite difference derivatives and derivatives for operations without specified frequencies to work correctly.  Since the finite-difference derivatives are now correct, we can see that the parameter-shift gradients never worked correctly.

### Additional contract requirements

- `qml.CommutingEvolution` must use the supplied evolution time and Hamiltonian to determine the applied evolution.
- Its time derivatives must be correct both for finite differences and when frequency information is inferred rather than supplied.
