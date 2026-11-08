Rule proposal: no-buffer-constructor
In the upcoming Node.js v6 release, the existing `Buffer()` constructors are being soft-deprecated (docs-only deprecation) and replaced with new `Buffer.alloc()`, `Buffer.allocUnsafe()` and `Buffer.from()` alternatives. I am adding a rule to Node.js' own eslint configuration to flag uses of the deprecated constructors (see: https://github.com/nodejs/node/pull/5740). The point has been raised that it may be worthwhile upstreaming this rule so that it can be of benefit to the ecosystem as a whole. Currently the rule is pretty simplistic and can be made a bit more robust if necessary.

The rule catches uses of the `Buffer()` constructor either as `new Buffer(...)` or simply `Buffer(...)` (without the new) and suggests using one of the new constructors instead.

If it is worthwhile, I can open a pull request to submit the rule here.

### Additional contract requirements

- Add a rule named `no-buffer-constructor` in module `lib/rules/no-buffer-constructor.js`.
