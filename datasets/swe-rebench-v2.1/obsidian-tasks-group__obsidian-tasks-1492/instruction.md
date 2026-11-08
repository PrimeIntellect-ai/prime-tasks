Make StatusRegistry easier to test
### Description

The StatusRegistry is a singleton and can only be accessed modified via a getInstance() method.

https://github.com/obsidian-tasks-group/obsidian-tasks/blob/5c5d28850045d38dca8a7fe90b9ab7c175077bdf/src/StatusRegistry.ts#L3-L22

This makes for convoluted test code, as every test needs to:

- reset the global state at the start, just in case someone else didn't
- restore it at the end, to be a good citizen




### Required Steps

I propose to retain the static instance, for minimal changes to the plugin code, but make the constructor public, to simplify the tests and also to allow production code to say things like 'give me the default statuses please'

And the simplify the existing tests.

### How to Test

_No response_

### Additional contract requirements

- `StatusRegistry` in `src/StatusRegistry.ts` must have a public constructor `StatusRegistry()` that can be called to create a new instance.
- A newly constructed `StatusRegistry` must be a fresh instance, independent of the global singleton returned by `StatusRegistry.getInstance()`: changes made to one instance must not affect the other.
- A newly constructed `StatusRegistry` must contain the default status types.
