Initial createReducer state is not frozen
Immer auto-freezes state when processed in a case reducer. However, we currently do not freeze the _initial_ state.  This means that it _is_ possible to mutate the initial state before any actions are dispatched.  Not sure if the mutation checker picks up on it or not.

Another issue is that I'm looking at updating the immutability and serialization checks to skip past frozen values for speed. If the initial state isn't frozen, we don't get the benefit there. Now, it's also likely that the initial state is almost empty so it won't take long to scan those values anyway, but I can't see a reason to _not_ freeze the initial state.

[HIDDEN]
