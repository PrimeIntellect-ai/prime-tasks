Attach `src` attributes to emitted `module`s and `cell`s
This isn't currently done in Amaranth (neither is it tracked) and with the [`$scopeinfo` support](https://github.com/YosysHQ/yosys/pull/4084) in Yosys this is newly relevant for simulation.

### Additional contract requirements

- Source locations supplied when adding children to a `Module` are retained for their instantiating cells, whether the children are anonymous or named.
- `Fragment.add_subfragment(self, subfragment, name=None, *, src_loc=None)` preserves a supplied source location so that it identifies where the child was added to its parent in the emitted cell.
- Every emitted RTLIL `module` and `cell` carries a `src` attribute. Each module declaration identifies where that module was defined, and each cell instantiating a module identifies where the child was added to its parent.


- For a top-level module named `top` with a submodule named `sub`, the emitted RTLIL must include an `attribute \\src ` attribute among the attributes preceding each declaration `module \\top`, `module \\top.sub`, and `cell \\top.sub \\sub`.
