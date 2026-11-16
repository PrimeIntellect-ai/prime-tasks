False positive with ContentSlotReused
Nullable lambdas make ContentSlotReused to report a false positive. Needs fixing + release asap.

For the time being, just use 0.4.12 (until 0.4.15 launches).

### Additional contract requirements

- Classify nullable lambdas by whether they are composable, not by nullability alone. A nullable ordinary (non-composable) lambda must not be reported merely because it is invoked in multiple branches.
- A nullable composable content lambda remains subject to `ContentSlotReused`: report its reuse across mutually exclusive branches or in multiple movable-content definitions, including when it is invoked with a safe call.
