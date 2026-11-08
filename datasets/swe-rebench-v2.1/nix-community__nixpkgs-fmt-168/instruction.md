remove line break after expanded let ... in
```nix
# One line, everyone's happy
let self = { }; in self
```


https://github.com/nix-community/nixpkgs-fmt/issues/65#issuecomment-507306029 suggests that we could consider `let ... in` just as an `assert ...;` or a `with ... ;` statement that does not indent the following body. In that case example 2 is inconsistent.

```nix
# input
# This should be okay if `let` is considered like a `with` or `assert`
let self = { }; in
self
```

```nix
# nix-fmt output
# But it is expanded :-(
let
  self = {};
in
self
```

Overall, it seems that the `let ... in body` is expanded (split across multiple lines as long as it is not written on one line. I think that expanding the `let ... in` part should be independent from expanding the body itself and from decoupling the `in` from the body.

The above example is made even worse by the fact that we do not indent toplevel let bodies (https://github.com/nix-community/nixpkgs-fmt/pull/108). The `self` really looks weird and could be on the same line as the `in`.

May I propose the following patterns ?

```nix
let foo = bar; in foo
```
```nix
let foo = bar; in
foo
```
```nix
let
  foo = bar;
in {
  bar = foo;
}
```

The implicit rule is that when the let+in construct is one one line, it behaves like a `with` or `assert`, and when it is on several lines (expanded form), no line break is enforced after the `in` (which means that line breaks are only enforced for a multi-line body after a single line let+in).
