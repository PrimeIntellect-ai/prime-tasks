LFRic-specific Dependency Analysis
As part of #2197, we are moving to using pointers to pass data to kernel calls so as to avoid accessing structures within an OpenACC region (e.g. `my_proxy%data`). However, the Dependence Analysis now sees that we are passing an array to a kernel and, by default, we give all such arguments read-write access (`Call.reference_accesses`). It therefore correctly identifies that this is a potential race condition (since it doesn't know which elements of the array are written to) and says the call cannot be safely executed in parallel.

Since the call is actually to an LFRic kernel (which are only permitted to write to data in the current column), we can do better:

 * If the field is on a discontinuous function space then the access is safe;
 * If the parent loop is over dofs then the access is safe;
 * If the parent loop is over cells of a single colour then the access is safe;

The potential solution to this is to encapsulate this domain knowledge in a domain specialisation of the dependence analysis.

### Additional contract requirements

Loops provide an `independent_iterations()` query that reports whether the loop's iterations can safely execute in parallel. For LFRic loops, a field access on a discontinuous function space is safe, as are loops over dofs and loops over cells of a single colour. A continuous-field write in an uncoloured cell loop is not safe for parallel execution.
