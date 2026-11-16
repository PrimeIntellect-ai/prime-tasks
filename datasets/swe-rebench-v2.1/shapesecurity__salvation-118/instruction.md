warn on duplicate declarations
`script-src a b; script-src b c` should produce a duplicate declaration warning, even though we have given it intersectional merge semantics (matching common implementation behaviour).

From [the spec](https://www.w3.org/TR/CSP2/#policy-parsing):

> If the set of directives already contains a directive whose name is a case insensitive match for directive name, ignore this instance of the directive and continue to the next token.

### Additional contract requirements

- When parsing `script-src a b; script-src b c`, the parser must record exactly one duplicate-directive warning in the supplied notices list, and that warning's `Notice.show()` must contain the text `Policy contains more than one script-src directive. All but the first instance will be ignored.`
- A later directive whose name matches an existing directive case-insensitively is ignored, not merged; the resulting policy retains the first directive and its values.
