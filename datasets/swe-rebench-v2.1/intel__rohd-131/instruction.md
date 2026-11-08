Simulator.reset does not wait for simulation to complete creating race condition
## Describe the bug
The `_simulationEndRequested` after reset is not set for run loop causing simulation to keep running even after it was asked to be ended.

## To Reproduce
Step 1) `simulator.endSimulation()`
Step 2) `simulator.reset()` before `simulationHasEnded`

## Expected behavior
After we call reset the simulation is not running anymore.

## Actual behavior
Previous simulation tries to run even after reset because it never ended.

### Additional contract requirements

- After `Simulator.reset()` completes, the simulator is back to its initial state: `Simulator.time` is `0`, `Simulator.simulationHasEnded` is `false`, and `Simulator.hasStepsRemaining()` is `false`.
