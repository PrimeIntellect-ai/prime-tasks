Feature request: enhance match to include multiple targets
This has previously been discussed at https://github.com/djc/askama/issues/711#issuecomment-1794340598 but I would like to move it to its own issue as it can be implemented separately.

The request is to enhance Askana's syntax for the `match` block (see https://djc.github.io/askama/template_syntax.html#match) to handle multiple targets in the same 'arm'.

See https://doc.rust-lang.org/reference/expressions/match-expr.html for the Rust syntax in the Reference Manual. Note that a match arm can have multiple targets; the object of this feature request is to replicate this in Askama. (I am not requesting 'match arm guards' (`if` clauses)).

So given code like
```
enum Suit {Clubs, Diamonds, Hearts, Spades}
```
one could write a template like
```
The card is
{% match suit %}
   {% when Suit::Clubs or Suit::Spades %}
     black
   {% when Suit::Diamonds or Suit::Hearts %}
     red
{% endmatch %}
```
Alternatively, `or` could be replaced by `|` in the proposed design, but I think Askama prefers keywords to symbols.

[HIDDEN]

There is some code around `heritage.rs(93)`. I'm not sure what it does, but it looks like it moves the match arms without change, so maybe it does not require any change.

Also, the documentation will need changing, of course. near `template_syntax.md(417)`*ff*.

The test could look something like the following (in `testing/tests/matches.rs)`, with the template above in `testing/templates/match-enum.html`).

```
enum Suit {Clubs, Diamonds, Hearts, Spades}
#[derive(Template)]
#[template(path = "match-enum.html")]
struct MatchEnumTemplate {
    item: Suit,
}

#[test]
fn test_match_enum() {
    let s = MatchEnumTemplate { item: Suit::Clubs};
    assert_eq!(s.render().unwrap(), "\nThe card is black\n");

    let s = MatchEnumTemplate { item: Suit::Hearts};
    assert_eq!(s.render().unwrap(), "\nThe card is red\n");

}
```

### Additional contract requirements

- The keyword separating multiple targets within a single `when` arm is `or`, as shown in the example above (e.g. `{% when Suit::Clubs or Suit::Spades %}`). The `|` symbol is not part of the accepted template syntax.
- A `when` arm with multiple targets matches when the value matches any one of those targets, and renders that arm's body.
