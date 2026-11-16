Axis values support for network diffs
We used the network diffing functionality of this library for our game jam game: https://prawl.itch.io/stellar-squeezebox which overall turned out great and it was really helpful for getting something off the ground quick!

Unfortunately, gamepad support was really lacking when diffing actions with a couple major issues:

A. There is no support for axis data for ActionDiff
B. ~~If you use an axis as a button (e.g. turn left) you can't set a deadzone or it stops being recognized on the server. Example:
  `SingleAxis::negative_only(GamepadAxisType::LeftStickX, 0.1).with_deadzone(deadzone)`~~ Was user error. See [comment](https://github.com/Leafwing-Studios/leafwing-input-manager/issues/342#issuecomment-1510452715)

I'd like to contribute towards this, so if you have any thoughts about how you want this to work let me know. (I'll probably taking a few days to relax now that the jam is over, so might be a bit)

### Additional contract requirements

- Action diffs must represent scalar action-value changes and dual-axis input data, in addition to binary pressed and released transitions.
- When a scalar action value or dual-axis input changes, the diff generator must report that change; it should not emit another update when that data is unchanged.
- The receiving side must apply received scalar action-value and dual-axis data diffs to the corresponding action state.
