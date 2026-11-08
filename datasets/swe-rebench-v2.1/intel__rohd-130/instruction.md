`WaveDumper` dumps improper vcd format for multi-bit values
## Describe the bug
Multi-bit values in dumped VCD files from `WaveDumper` are printed incorrectly.

Instead of things like `0101` it prints `1'b01'b11'b01'b1`, which is a result of a `toString` change to `LogicValue`.

## To Reproduce
Dump any waveform of multi-bit signals and look at the dumped waveform in a waveform viewer.

## Expected behavior
Properly dumped waves.

## Actual behavior
Corrupted waves, shows "------" in GtkWave

**Additional context**
The existing tests for `WaveDumper` did not test multi-bit values, only single bit values, which is how this bug was missed when it was introduced in v0.3.0.
