`require-meta-type` don't support spread operator
When filling `meta` object using a spread operator instead of explicitly set the fields, the eslint validator fails. It should look for the content of the spread and see that the required fields are there, instead of forcing to set them explicitly.

### Additional contract requirements

Add a public function `evaluateObjectProperties(objectNode, scopeManager)` in `lib/utils.js`. It returns an array of the object's direct property nodes and expands spread elements in their original positions when the spread argument resolves through `scopeManager` to a statically known object literal. Expanded properties retain their source order relative to direct properties and other spreads. A spread that cannot be resolved, or resolves to a value that is not an object literal, contributes no properties. If `objectNode` is missing or is not an object literal, return an empty array.
