Add option to skip serializability check for state slices
The `redux-immutable-state-invariant` middleware has an option for skipping checks for selected slices of state:  https://github.com/leoasis/redux-immutable-state-invariant#api .  However, our homegrown `serializable-state-invariant` middleware only allows determining if a given value is serializable, and skipping specific actions, not skipping slices of state.

Per https://stackoverflow.com/questions/59773345/react-toolkit-and-redux-first-router , it looks like Redux-First-Router in particular tries to store thunks directly in the store. It's a bad idea, but seems like we should at least update the serializable middleware to accept a list of state slices to skip.

Since our serializable middleware was directly inspired by the immutable middleware to begin with, we should be able to look at how the immutable middleware implements this, and reuse the same approach.

### Additional contract requirements

- Add an optional `ignoredPaths` option to the serializability middleware. It accepts dot-separated state paths; values at those paths and their descendants are exempt from serializability checks, while other state paths remain checked.
