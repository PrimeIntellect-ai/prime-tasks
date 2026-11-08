Have an easy way to see if an entire ActionLike is disabled
## What problem does this solve?

https://github.com/Leafwing-Studios/leafwing-input-manager/pull/456 changed the way that disabling actions was handled, from using a `ToggleActions<A>` resource to adding a `disabled` flag **per Action** (not ActionState)
I think there still should be a way to disable an entire `ActionLike`.

Currently we only have the method `disabled(a: &Action)` to check if a given Action is disabled, but very often we would want to check quickly if the entire set of Actions is disabled for a given entity.

One use-case: in networking, if the entire set of actions is disabled, I would like to stop sending network packets for a given entity.
I guess currently I could iterate through all Actions and check if all of them are disabled, but that doesn't seem elegant.

## What solution would you like?

Maybe the `ActionState` should contain additional data that is shared between all Actions, on top of the existing HashMap
```
pub struct ActionState<A: Actionlike> {
    /// The [`ActionData`] of each action
    action_data: HashMap<A, ActionData>,
}
```

[HIDDEN]

Then I could easily disable the entire ActionState, instead of disabling each Action individually.



## Related work

Related to https://github.com/Leafwing-Studios/leafwing-input-manager/issues/553

### Additional contract requirements

- `ActionState<A>` (in `leafwing_input_manager::action_state`, also re-exported from the prelude) provides a method `disabled(&self) -> bool` that reports whether the entire action state is currently disabled.
- `ActionState<A>` provides a method `disable(&mut self)` that disables the entire action state and resets every action's value to its default: buttons are released, axes are set to `0`, and dual-axes are set to `Vec2::ZERO`.
- `ActionState<A>` provides a method `enable(&mut self)` that re-enables the entire action state. Actions that were individually disabled remain disabled.
- `ActionState<A>` provides methods `disable_all_actions(&mut self)` and `enable_all_actions(&mut self)` that disable or enable every action individually. Disabling resets each action's value to its default.


- A newly default-constructed `ActionState<A>` is enabled, so `disabled()` returns `false`.

- While an entire `ActionState` is disabled, subsequent input updates must not make any of its actions active or restore non-default values.
