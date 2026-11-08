Add loop controls
`break` and `continue`: see http://jinja.pocoo.org/docs/dev/templates/#loop-controls in Jinja2

This would avoid ugly things like https://github.com/Keats/book/blob/master/templates/page.html#L29-L43

### Additional contract requirements

- The parser exposes `TeraParser::parse(rule, input)` in `src/parser/mod.rs`, where `rule` is a `Rule` variant and `input` is a template fragment. It must recognize the grammar rules `Rule::break_tag` and `Rule::continue_tag`, parsing `{% break %}` and `{% continue %}` respectively.
- The parser exposes `parse(template)` in `src/parser/mod.rs`, returning the template AST. A template containing `{% break %}` or `{% continue %}` inside a loop must parse successfully and produce a `Node::Break` or `Node::Continue` node in the loop body.
- When `{% break %}` or `{% continue %}` appears outside a loop, parsing must fail with an error message containing the exact phrase `expected a template`.
- When either tag appears outside a loop at the start of the template, the error message must also contain `1:1` and the offending tag exactly as written (`{% break %}` or `{% continue %}`).
