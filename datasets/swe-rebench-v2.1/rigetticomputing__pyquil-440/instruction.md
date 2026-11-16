Should Pragmas accept QubitPlaceholders?
I was experimenting with adding a fencing Pragma, and found it useful for pragmas to allow qubitplaceholders in their args. For most use cases this is probably moot, since probably 99% of pragmas written in pyquil end up being parsed by our compiler, but if people are writing their own backend for interpreting quil programs, having pragmas accept qubitplaceholders seems like a good idea. e.g. something like the following:

```
p = Program()
q = QubitPlacholder()
q2 = QubitPlacholder()
p.inst(X(q))
p.inst(Pragma("FENCE", [q, q2]))
p.inst(X(q2))
```
I found this useful in prototyping two qubit randomized benchmarking, where I might want better timing control over when gates and measurements happen, coordinated across two qubits.
