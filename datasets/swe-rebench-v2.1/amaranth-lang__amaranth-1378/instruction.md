Adding simulator processes after starting the simulation is not well-defined
... and should probably be rejected with a diagnostic.

I realized that we technically permit this while writing https://github.com/amaranth-lang/rfcs/pull/67#issuecomment-2139178160, and I don't think we should; among other things it breaks the semantics of `reset` (which rolls back the simulation to the point before `run()`).

### Additional contract requirements

- `Simulator.add_clock(period, *, phase=None, domain="sync", if_exists=False)`,
  `Simulator.add_testbench(constructor, *, background=False)`, and
  `Simulator.add_process(process)` must raise `RuntimeError` when the
  simulation has been advanced since its creation or its last reset. The messages must be
  exactly `Cannot add a clock to a running simulation`,
  `Cannot add a testbench to a running simulation`, and
  `Cannot add a process to a running simulation`, respectively.
- `Simulator.reset()` returns the simulation to the state before `run()` was called, so after a
  reset these methods may be called again.
