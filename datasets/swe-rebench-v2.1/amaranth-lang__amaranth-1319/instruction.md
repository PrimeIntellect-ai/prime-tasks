pysim LHS compiler miscompiles `Slice` of  `SwitchValue`
Add to `test_sim.py` `SimulatorUnitTestCase`:

```py
    def test_array_lhs_heterogenous_slice(self):
        l = Signal(1, init=1)
        m = Signal(3, init=4)
        n = Signal(5, init=7)
        array = Array([l, m, n])
        stmt = lambda y, a, b: [array[a].as_value()[2:].eq(b), y.eq(Cat(*array))]
        self.assertStatement(stmt, [C(0), C(0b000)], C(0b001111001, 9))
        self.assertStatement(stmt, [C(1), C(0b010)], C(0b001110001, 9))
        self.assertStatement(stmt, [C(2), C(0b100)], C(0b100111001, 9))
```

[HIDDEN]

```
  File "/tmp/amaranth_pysim_sw1hg_w2", line 5, in run
    test_0 = 0x1 & next_4
                   ^^^^^^
NameError: name 'next_4' is not defined
```

```py
def run():
    next_0 = 1
    next_1 = 4
    next_2 = 0
    test_0 = 0x1 & next_4
    rhs_switch_1 = 0
    match test_0:
        case 0b00:
            rhs_switch_1 = (0x1 & next_0)
        case 0b01:
            rhs_switch_1 = (0x7 & next_1)
    test_2 = 0x1 & slots[4].curr
    match test_2:
        case 0b00:
            next_0 = 0x1 & (rhs_switch_1 & -0x5 | ((0x1 & (0x1 & slots[3].curr)) << 2))
        case 0b01:
            next_1 = 0x7 & (rhs_switch_1 & -0x5 | ((0x1 & (0x1 & slots[3].curr)) << 2))
    next_2 = 0x1ff & (0x1ff & (((0x1 & slots[0].curr) << 0) | ((0x7 & slots[1].curr) << 1) | ((0x1f & slots[5].curr) << 4)))
    slots[0].set(next_0)
    slots[1].set(next_1)
    slots[2].set(next_2)
```

### Additional contract requirements

- Assignments to slices of dynamically indexed heterogeneous arrays must work correctly and produce the values asserted in the examples above.
