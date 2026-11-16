Generate action diffs for only a filtered set of entities
## What problem does this solve?

In a networked game, there may be cases where actions on some entities should remain local, while actions on others should get diffed and have `ActionDiffEvent<A>`s generated.

Currently, `SummarizedActionState<A>::summarize` & `generate_action_diffs<A>` summarize and emit action diffs for every entity with `ActionState<A>`, which lacks the degree of control I'm looking for.

## What solution would you like?

I'd like to be able to filter which entities get action diffs generated.

Since we need to add the `generate_action_diffs<A>` system manually anyway, this seems to be the best place to specify it, e.g. `generate_action_diffs<A, Without<NotActionSender<A>>` (where `NotActionSender<A>` is an example of a tag component that marks anything for which action diff events should not be sent).

## How could this be implemented?

Implement a new `generate_action_diffs_filtered<A, F = QueryFilter>` function, [HIDDEN] User code can choose between adding the `generate_action_diffs<A>` or `generate_action_diffs_filtered<A, F>` systems according to their needs.

See PR #601.

## What alternatives have you considered?

- Require user code to use different Actionlikes to differentiate actions that should be diffed and those that shouldn't, and only call `generate_action_diffs` on the former. It's a pretty big burden on the user side though.
- Create a new tag component in this crate (e.g. `NotActionSender<A>`, or a better name) that users can tag entities with, and have `generate_action_diffs<A>` always ignore entities with this tag. A bit less flexible.
