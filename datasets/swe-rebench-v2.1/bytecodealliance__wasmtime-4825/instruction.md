Limit type-based recursion in the component model
Currently the component model has no limit to type-bsaed recursion other than the "width" of a type and the number of types the type section is allowed to have. The fuzzers have subsequently studiously been finding all the issues with that in the implementation of the component model within Wasmtime. Wasmtime has a number of methods right now which recursively process a type which can lead to stack overflow for deeply nested types such as:

* the `Arbitrary for Type` implementation
* The `{Lower,Lift} for Val` implementations
* The compilation of adapter trampolines

In each of these cases it's not 100% clear if there's an easy way to switch stack-based recursion to heap-based recursion. So far switching to heap-based recursion or alternative methods has been the go-to for fixing fuzz-bugs like this (https://github.com/bytecodealliance/wasmtime/pull/4657 https://github.com/bytecodealliance/wasmtime/pull/4658 https://github.com/bytecodealliance/wasmtime/pull/4708 https://github.com/bytecodealliance/wasmtime/pull/4694) but this seems over time like it's starting to be untenable.

To solve all these issues the conclusion that @fitzgen @lukewagner and I reached awhile back was to simply limit recursion of type hierarchies in the component model entirely. This is a big hammer to use but would definitely fix all of the related issues here, in addition to the recent crop of fuzz-bugs which are getting harder and harder to fix via alternative means. This also seems to mirror what the GC proposal for wasm is doing where limits are placed on the type recursion there as well.

One option to implement this would be an error from `wasmparser` during validation but I think for now it may be best represented as an error from Wasmtime itself due to that being where all the fuzz bugs are. If we feel it's necessary this could also be moved to `wasmparser` instead.

One bit of trickiness here is that we'll need to update `Arbitrary for Type` to have some limited recursion, and I'm not sure how to do that with `#[derive]` without a thread-local based solution. This may be a case where it's better to have a custom method taking `Unstructured` with a `depth` where the `depth` filters out some possible types to generate.

### Additional contract requirements

- Component-model type hierarchies must have a finite nesting bound, and a hierarchy 1,000 levels deep must be rejected.
- Recursive type values produced by the `Arbitrary for Type` generator must have bounded nesting; generated values must not contain 256 nested type constructors.
