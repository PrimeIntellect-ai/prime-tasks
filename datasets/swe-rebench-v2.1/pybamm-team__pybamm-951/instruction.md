Recalculate initial conditions during parameter sweeps
During parameter sweeps, initial conditions only get calculated once (at the first solve), and then are fixed for all future solves. They should be recalculated each time if the algebraic equations or initial conditions change when an input changes.

### Additional contract requirements

On every solve in a parameter sweep, calculate input-dependent initial conditions from that solve's current inputs. For differential-algebraic models, if the inputs change an algebraic equation, the initial algebraic state must satisfy that equation for the current inputs.
