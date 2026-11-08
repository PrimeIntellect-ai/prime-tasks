Support doc(alias)-based completion
To put it simply, I have some funny named registers like `PORTPMSC` but want to give them real names, in this case something like `PortPowerManagementStatusControl` (not exactly, but you get the idea).
```rust
doc(alias("PORTPMSC"))
struct PortPowerManagementStatusControl { ... }
```
Sometimes the name of the thing and its abbreviation in a specification is completely different though, so code completion will only work with the name in code, but I would like people to be able to use the spec abbreviations as well.

To get to the point: Where would I need to start looking to implement this? I.e. where in this repo is the code-completion handled and where the attribute parsing or generally attribute info?

### Additional contract requirements

- Add a type `DocExpr` in module `hir_def::attr`.
- Add a method `DocExpr::parse` in module `hir_def::attr` that parses the token tree of a `#[doc(...)]` attribute into a `DocExpr`.
- Add a method `DocExpr::aliases(&self) -> &[SmolStr]` in module `hir_def::attr` that returns the alias strings declared by the doc expression, and an empty slice when the expression declares no aliases.
- Both `#[doc(alias = "x")]` and `#[doc(alias("x"))]` expose the alias `x`.
- A completion item for a definition that has doc aliases shows them appended to its label as `Name (alias Alias1, Alias2, ...)`, listing the aliases in the order they are declared.
