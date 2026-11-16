OptimizeSwapBeforeMeasure needs multiple invocations
The `OptimizeSwapBeforeMeasure` pass is supposed to commute quantum SWAP gates that immediately precede measurements, past the measurements, and instead convert them to classical swap (i.e.just retarget the measurement clbit).

However this should be generalized to work with any permutation that happens before the measurements, not just one swap layer. I made this work by invoking it many times for the example below, but really one invocation should be smart enough to remove all the swaps ([HIDDEN]).

```py
from qiskit import QuantumCircuit
from qiskit.transpiler.passes import OptimizeSwapBeforeMeasure, Depth, FixedPoint
from qiskit.transpiler import PassManager

circ = QuantumCircuit(8, 8)
circ.swap(3, 4)
circ.swap(6, 7)
circ.swap(0, 1)
circ.swap(6, 7)
circ.swap(4, 5)
circ.swap(0, 1)
circ.swap(5, 6)
circ.swap(3, 4)
circ.swap(1, 2)
circ.swap(6, 7)
circ.swap(4, 5)
circ.swap(2, 3)
circ.swap(0, 1)
circ.swap(5, 6)
circ.swap(1, 2)
circ.swap(6, 7)
circ.swap(4, 5)
circ.swap(2, 3)
circ.swap(3, 4)
circ.swap(3, 4)
circ.swap(5, 6)
circ.swap(1, 2)
circ.swap(4, 5)
circ.swap(2, 3)
circ.swap(5, 6)
circ.measure(range(8), range(8))
print(circ)

_depth_check = [Depth(), FixedPoint('depth')]
_opt = [OptimizeSwapBeforeMeasure()]
def _opt_control(property_set):
    return not property_set['depth_fixed_point']

pm = PassManager()
pm.append(_depth_check + _opt, do_while=_opt_control)  # should not need this do_while
print(pm.run(circ))
```

```
                    ┌─┐
q_0: ─X──X─────X────┤M├─────────────────────────────────
      │  │     │    └╥┘         ┌─┐
q_1: ─X──X──X──X──X──╫─────X────┤M├─────────────────────
            │     │  ║     │    └╥┘      ┌─┐
q_2: ───────X──X──X──╫──X──X─────╫──X────┤M├────────────
               │     ║  │        ║  │    └╥┘┌─┐
q_3: ─X─────X──X─────╫──X──X──X──╫──X─────╫─┤M├─────────
      │     │        ║     │  │  ║        ║ └╥┘┌─┐
q_4: ─X──X──X──X─────╫──X──X──X──╫──X─────╫──╫─┤M├──────
         │     │     ║  │        ║  │     ║  ║ └╥┘┌─┐
q_5: ────X──X──X──X──╫──X──X─────╫──X──X──╫──╫──╫─┤M├───
            │     │  ║     │     ║     │  ║  ║  ║ └╥┘┌─┐
q_6: ─X──X──X──X──X──╫──X──X─────╫─────X──╫──╫──╫──╫─┤M├
      │  │     │     ║  │ ┌─┐    ║        ║  ║  ║  ║ └╥┘
q_7: ─X──X─────X─────╫──X─┤M├────╫────────╫──╫──╫──╫──╫─
                     ║    └╥┘    ║        ║  ║  ║  ║  ║
c: 8/════════════════╩═════╩═════╩════════╩══╩══╩══╩══╩═
                     0     7     1        2  3  4  5  6
           ┌─┐
q_0: ──────┤M├───────────────
        ┌─┐└╥┘
q_1: ───┤M├─╫────────────────
     ┌─┐└╥┘ ║
q_2: ┤M├─╫──╫────────────────
     └╥┘ ║  ║    ┌─┐
q_3: ─╫──╫──╫────┤M├─────────
      ║  ║  ║    └╥┘      ┌─┐
q_4: ─╫──╫──╫─────╫───────┤M├
      ║  ║  ║ ┌─┐ ║       └╥┘
q_5: ─╫──╫──╫─┤M├─╫────────╫─
      ║  ║  ║ └╥┘ ║ ┌─┐    ║
q_6: ─╫──╫──╫──╫──╫─┤M├────╫─
      ║  ║  ║  ║  ║ └╥┘┌─┐ ║
q_7: ─╫──╫──╫──╫──╫──╫─┤M├─╫─
      ║  ║  ║  ║  ║  ║ └╥┘ ║
c: 8/═╩══╩══╩══╩══╩══╩══╩══╩═
      0  1  2  3  4  5  6  7
```

### Additional contract requirements

- A single invocation of `OptimizeSwapBeforeMeasure` must handle a composed sequence of SWAP gates before measurements, remove those SWAP gates, and retarget the measurements so each measured value is written to the same classical bit as before.
