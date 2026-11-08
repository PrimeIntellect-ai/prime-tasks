shape method for Interferometer
### Feature details

The Interferometer template does not have a `shape` method to give out the required parameters' shapes.
It would be helpful to have this method as three parameters are required that have two different shapes.

### Implementation

The interferometer template is not defined as a class, so probably, it'll need restructuring before this can be implemented.

### How important would you say this feature is?

1: Not important. Would be nice to have.

### Additional information

_No response_

### Additional contract requirements

- `Interferometer` is a `CVOperation` (an `Operation` subclass). Instantiating it enqueues a single `Interferometer` operation rather than its elementary gates; the elementary gates are produced by `Interferometer.expand()`. As a consequence, other templates that instantiate `Interferometer` (for example `CVNeuralNetLayers`) contain `Interferometer` operations in their expansion.
