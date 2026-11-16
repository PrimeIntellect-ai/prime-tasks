Add regular expression support
This should work:


     if ( "Steve" ~= /steve/i ) {
           ..

We should also see:

      print( type( /foo/ ) ) ;   -> "regexp"

(So it is a distinct type, not a string.)

### Additional contract requirements

- The lexer package `github.com/skx/monkey/lexer` exposes `New(input string) *Lexer` and the method `(*Lexer).NextToken() token.Token`, which returns the next token from the input.
- A regular-expression literal is returned by `NextToken` as a token whose type is `REGEXP` (the `token.REGEXP` constant in package `github.com/skx/monkey/token`). The literal is normalised: `/steve/i` yields the literal `(?i)steve`, `/steve/m` yields `(?m)steve`, and `/steve/mi` yields `(?mi)steve`. Repeated flags are collapsed, so `/steve/miiiiiiiiiiiiiiiiimmmmmmmmmmmmmiiiii` yields `(?mi)steve`.
- An unterminated regular expression such as `/steve` in `if ( f ~= /steve )` is returned as a token whose type is `REGEXP` with the literal `unterminated regular expression`.
- The `~=` operator is returned by `NextToken` as a token whose type is `CONTAINS` (the `token.CONTAINS` constant) with the literal `~=`.
- A `/` that begins a division is returned as a token whose type is `SLASH` with the literal `/`, and is not treated as the start of a regular expression.
