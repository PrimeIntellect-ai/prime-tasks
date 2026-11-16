Option to turn it off
Sometime it would be nice to be able to turn Revise off on the fly.  For instance if I want to compare one branch vs another.  Or I want to run the code again before the changes take effect to then compare to after.

Just a suggestion, feel free to close as won't-fix.

### Additional contract requirements

- Revise provides a public runtime switch `Revise.active`, a global boolean flag read and assigned as `Revise.active[]`, that turns Revise's automatic code updating off and back on.
- While `Revise.active[]` is `false`, source changes made to a tracked package are not applied by `revise` (calling `Revise.revise` leaves the previously loaded definitions unchanged).
- After `Revise.active[]` is set back to `true`, the source changes made in the meantime take effect on the next revision.
