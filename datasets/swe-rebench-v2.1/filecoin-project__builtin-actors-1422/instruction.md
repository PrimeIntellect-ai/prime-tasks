Multisig: Propegate error value on failure
We currently propagate the exit code, but not error value, when a message sent by a multisig fails. This used to be correct, but now that we can return error _values_ on failure, we should propagate those here:

https://github.com/filecoin-project/builtin-actors/blob/405f76a1fce03e6c007275533cdc15ede396b059/actors/multisig/src/lib.rs#L475-L489

[HIDDEN]
