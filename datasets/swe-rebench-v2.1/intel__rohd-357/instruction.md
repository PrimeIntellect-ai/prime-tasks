Add an enable signal to `FlipFlop`
### Motivation

Along the same lines as https://github.com/intel/rohd/issues/69

It would be nice to have an enable signal optionally provided as part of the built-in `FlipFlop`.

### Desired solution

Add an optional enable signal to `FlipFlop`.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

Expose the optional enable input as the named parameter `en` on `FlipFlop`. When `en` is high at a rising clock edge, the output captures the data input; when it is low, the output retains its previous value. Omitting `en` leaves the flip-flop always enabled. Enable-controlled operation must support multi-bit data inputs as well as one-bit inputs.
