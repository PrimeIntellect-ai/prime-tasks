Pysim should reject async generators
While converting some testbenches from generator-based to `async`-based for [pytest-amaranth-sim](https://github.com/cr1901/pytest-amaranth-sim), I accidentally forgot to remove a `yield` on one of them:

```python
@pytest.fixture(params=[pytest.param(MulTbArgs())], ids=mul_tb_id)
def mul_tb(mod, request):
    """The multiplier testbench proper. Receives arguments via request."""
    async def testbench(s):
        m = mod

        if m.registered:
            await s.tick()
        else:
            await s.delay(0.1)

        s.set(m.a, request.param.a_in)
        s.set(m.b, request.param.b_in)

        if m.registered:
            await s.tick()
        else:
            await s.delay(0.1)

        # assert s.get(m.o) == request.param.o_out
        assert (yield m.o) == request.param.o_out

    return testbench
```

Running a simulation with this testbench currently fails with an unhelpful ` TypeError: mul_tb.<locals>.testbench() missing 1 required positional argument: 's'`.

In reality, what happened is "forgetting to remove a `yield` turns the testbench into an async generator, and `Simulator.add_process` [treats it as](https://github.com/amaranth-lang/amaranth/blob/e2b47c1a9ea319f8165d00363768654f85d23eb1/amaranth/sim/core.py#L46-L54) as a plain-old-generator". Plain-old-generator testbenches don't expect any input arguments, but `async`-based testbenches _do_ expect a `sim` argument, which is missing which that testbench is run. [Agreed-upon fix](https://libera.irclog.whitequark.org/amaranth-lang/2024-05-21#1716267918-1716268945) is to not allow async generators, which in and of itself will give a better error message.
