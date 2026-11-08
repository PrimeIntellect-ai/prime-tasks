Thread assertion called inconsistently between RT and compiled backends.
RT calls thread assertion in its single-thread caching provider _unconditionally_, while generated code would make the call _only upon actual construction_ - if value is not yet initialized.

Need to fix the inconsistency one way or the other.

### Additional contract requirements

The runtime and generated backends must make the same thread-assertion decision for equivalent accesses to initialized values. Either shared policy is acceptable: invoking the assertion on every access, or invoking it only when construction is needed.
