goto previous flow/step
**Is your feature request related to a problem? Please describe.**
On top of #154 it would be useful to be able to go back to the previous place (step/flow), not necessarily resetting whatever was done inbetween (so not true backtracking) but at least be able to retrieve the place where you are coming from.

For instance, it would be interesting to be able to be able to quickly go to some centralized flow/step that is used in a lot of places, and at the end of that, go back to where you came from to continue the regular flow.

**Describe the solution you'd like**
To be discussed (some solution that plays nice with #154)

### Additional contract requirements

- The CSML language provides a `previous` statement with two forms: `previous flow` and `previous step`. `previous flow` returns execution to the flow that was running before the current flow. `previous step` returns execution to the step that was running before the current step.
