struggling to understand source of an error
https://github.com/q3w3e3/amaranthSieve/blob/e1dbdbd0e990d9dbdeb7c2e92550d1058a265ef5/src/amaranth_sieve/sieve2.py

```
% pdm run test
================================================ test session starts =================================================
platform darwin -- Python 3.12.4, pytest-8.2.2, pluggy-1.5.0
rootdir: /Users/q3w3e3/Stuff/amaranthSieve
configfile: pyproject.toml
collected 1 item

tests/test_sieve.py F                                                                                          [100%]

====================================================== FAILURES ======================================================
____________________________________________________ test_sieve2 _____________________________________________________

    def test_sieve2():
        sieve2 = Sieve2()

        async def testbench(ctx):
            while ctx.get(~sieve2.done):
                await ctx.tick()


        sim2 = Simulator(sieve2)
        sim2.add_clock(period=1.667e-7)
        sim2.add_testbench(testbench)
        with sim2.write_vcd("sieve2.vcd"):
>           sim2.run_until(1.667e-7 * 200)

tests/test_sieve.py:18:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
.venv/lib/python3.12/site-packages/amaranth/sim/core.py:313: in run_until
    self.advance()
.venv/lib/python3.12/site-packages/amaranth/sim/core.py:330: in advance
    return self._engine.advance()
.venv/lib/python3.12/site-packages/amaranth/sim/pysim.py:692: in advance
    self.step_design()
.venv/lib/python3.12/site-packages/amaranth/sim/pysim.py:683: in step_design
    vcd_writer.update_memory(now_plus_deltas, change.state.memory,
.venv/lib/python3.12/site-packages/amaranth/sim/pysim.py:259: in update_memory
    self.vcd_writer.change(vcd_var, timestamp, var_value)
.venv/lib/python3.12/site-packages/vcd/writer.py:353: in change
    val_str = var.format_value(value, self._check_values)
.venv/lib/python3.12/site-packages/vcd/writer.py:669: in format_value
    value_str = _format_scalar_value(value, self.size, check)
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

value = -170, size = 8, check = True

    def _format_scalar_value(value: ScalarValue, size: int, check: bool) -> str:
        if isinstance(value, int):
            max_val = 1 << size
            if check and (-value > (max_val >> 1) or value >= max_val):
>               raise ValueError(f'Value ({value}) not representable in {size} bits')
E               ValueError: Value (-170) not representable in 8 bits

.venv/lib/python3.12/site-packages/vcd/writer.py:734: ValueError
============================================== short test summary info ===============================================
FAILED tests/test_sieve.py::test_sieve2 - ValueError: Value (-170) not representable in 8 bits
================================================= 1 failed in 0.10s ==================================================

```

### Additional contract requirements

- Memory initializer values must be converted according to the declared cell shape, including its width and signedness. Values must not remain as out-of-range raw integers that cannot be represented by the cell during simulation or VCD serialization.
