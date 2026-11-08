build: warn/error if Mem.Index is set but Mem.Scale is 0
An easy mistake to do is to create a `Mem{Base:x, Index:Idx}` and forget to set the Scale.

I can't see the `Scale:0` being useful, so maybe just error?

### Additional contract requirements

The validation must be applied by the build. The build's compile pass is the
exported `Compile` pass in package `pass` (the pass used by `build.Main`).
Executing `pass.Compile` on a file that contains an instruction with a memory
operand whose `Index` is non-nil and whose `Scale` is zero must return an error
whose message includes "index register with scale 0". Likewise, a memory
operand with a nil `Base` must cause `pass.Compile` to return an error whose
message includes "missing base".
