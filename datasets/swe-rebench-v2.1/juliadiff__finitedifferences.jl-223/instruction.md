Mutation of input arguments
Code like this https://github.com/JuliaDiff/FiniteDifferences.jl/blob/c7a4624092d90b6d49d5701967982226231d4478/src/grad.jl#L18

mutates the input argument, but before returning makes sure the input argument is restored to its original value. However, if the user-provided function errors, the input argument is left in a mutated state, which can cause bugs that are very hard to detect.
