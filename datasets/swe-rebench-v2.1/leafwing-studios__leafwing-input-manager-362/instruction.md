Adding inversion to mouse and gamepad axes
## What problem does this solve?

I want to implement keyboard and mouse control for a small game. I would like to give the user the choice of inverting the mouse axes independently from the keyboard input. In ego shooters some people like it to move the mouse forward to look up, others move the mouse backwards to look up.

## What solution would you like?

When setting the `InputMap` it would be nice to be able to set some axes to inverted.

## How could this be implemented?

A boolean `inverted` field in `SingleAxis` might already provide this feature. This can be set to `true` to mark this axis as being inverted.

## What alternatives have you considered?

Currently I implement custom `PitchInverted` action to represent the inverted axis for mouse only. This is a workaround and I would prefer a built-in solution, that is easily switchable by user choice.

## Related work

Using `SingleAxis` to solve this would enable inversion not only for mouse but also for all gamepad axes. Inversion could be useful for them as well.
