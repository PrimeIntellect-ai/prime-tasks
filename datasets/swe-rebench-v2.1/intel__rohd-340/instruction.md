`SynthBuilder` should check modules are already built
### Describe the bug

It's possible to generate outputs using a `Synthesizer` and `SynthBuilder` rather than through `Module.generateSynth`.  However, the `SynthBuilder` does not check that `Module.build` is called, only `generateSynth` does.  This can produce unexpected outputs (e.g. SystemVerilog with no submodules) without any helpful error message indicating why.

### To Reproduce

Use `SynthBuilder` to generate output verilog without calling `build` on the `Module`.

### Expected behavior

`ModuleNotBuiltException` is thrown

### Actual behavior

Silent incorrect results

### Additional: Dart SDK info

_No response_

### Additional: pubspec.yaml

_No response_

### Additional: Context

_No response_
