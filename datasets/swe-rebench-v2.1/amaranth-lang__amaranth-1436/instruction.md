Connect statements such as `wiring.connect(wiring.flipped(self.write), inner.w_stream)` silently do nothing
Note the missing first argument `m`.

This has cost me half a hour of bug searching :(
