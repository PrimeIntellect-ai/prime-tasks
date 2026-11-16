ActorRef::get_children() clears children record from supervision tree
**Describe the bug**

I'm not sure if this is intentional, but it's definitely a footgun. If I call `some_actor.get_children()` twice, then the second time returns an empty Vec. The children actors are still running and points to the original parent (half unlinked).

**To Reproduce**
Steps to reproduce the behavior:
1. Create an actor tree
2. On root actor, call `root.get_children()`
3. `assert_eq!(first_children_len, second_children_len)`
4. See error

**Expected behavior**

There should be a  non-destructive way to retrieve the list of children actors.

**Additional context**

https://github.com/slawlor/ractor/blob/main/ractor/src/actor/supervision.rs#L140
