Add support for redefining the same variable with `let` (just as Rust permits)
[Discovered while working on #315 and #327.]

The following statements, although allowed by Rust, are disallowed by `askama`:
~~~~
{% let x = 1 %}
{% let x = 2 %}
~~~~

The failure is:
~~~~
cannot assign twice to immutable variable
help: make this binding mutable: `mut x`
~~~~
