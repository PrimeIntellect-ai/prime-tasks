The `parent` resource option is undefined inside a transform
`parent` is always `undefined` inside `registerResourceTransform` (Node.js).

It looks like the engine isn't passing this through.
