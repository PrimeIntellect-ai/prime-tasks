pysim: testbench-only signals are not placed at root level on the VCD file
Consider:
```python
from nmigen import Signal, Module
from nmigen.sim import Simulator

m = Module()
s = Signal()
t = Signal()
m.d.sync += s.eq(1)


def process():
    yield t.eq(1)


for engine in ["pysim", "cxxsim"]:
    sim = Simulator(m, engine=engine)
    sim.add_clock(1e-6)
    sim.add_sync_process(process)
    with sim.write_vcd(f"bug17.{engine}.vcd", traces=[s, t]):
        sim.run()
```

On PySim, both `s` and `t` are placed under the `top`module.
On CXXSim, `t` is at the root.

The generated GTKWave document (if any) correctly display the trace, but an already existing manually-generated document would need modification, which is inconvenient.

### Additional contract requirements

When PySim writes a VCD, a testbench-only signal included in `traces` must appear at the VCD top level, outside the design's `top` scope. Signals belonging to the design remain inside the `top` scope.
