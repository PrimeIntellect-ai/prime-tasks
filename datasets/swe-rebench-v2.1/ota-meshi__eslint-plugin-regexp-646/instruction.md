Force one grapheme in the disjunction of string literals
**Motivation**
<!-- A clear and concise description of the problem the new rule is supposed to solve. -->

It may be useful to be able to force the disjunction of string literals to use only strings that humans recognize as single characters.

**Description**
<!-- A clear and concise description of the new rule. -->

It is possible to use strings of two or more characters in the disjunction of string literals, but normal disjunction is also possible. (However, there are differences in the evaluation order.)
Forcing a single character to be used in the disjunction of string literals allows people to distinguish between uses.

I think it is better to implement the rule by using `Intl.Segmenter` and allowing it if it is recognized as one grapheme.

**Examples**

<!-- Add a few examples of regexes that the rule does and does not report. -->

```js
/* ✓ GOOD */
var foo = /[\p{RGI_Emoji}--\q{🇦🇨|🇦🇩|🇦🇪|🇦🇫|🇦🇬|🇦🇮|🇦🇱|🇦🇲|🇦🇴|🇦🇶|🇦🇷|🇦🇸|🇦🇹|🇦🇺|🇦🇼|🇦🇽|🇦🇿|🇧🇦|🇧🇧|🇧🇩|🇧🇪|🇧🇫|🇧🇬|🇧🇭|🇧🇮|🇧🇯}]/v

/* ✗ BAD */
var foo = /[\q{abc|def}]/v
```

### Additional contract requirements

- The rule is exposed as `regexp/grapheme-string-literal` and is registered in the
  plugin's public `rules` export (from `lib/index.ts`), keyed by the rule name
  `grapheme-string-literal`.
- A string alternative is reported exactly when it consists of more than one
  grapheme. Alternatives consisting of zero graphemes (empty) or exactly one
  grapheme are not reported.
- When a string alternative is reported, the diagnostic message is exactly:
  "Only single characters and graphemes are allowed inside character classes. Use regular alternatives (e.g. `{{alternatives}}`) for strings instead."
  where `{{alternatives}}` is `(?:` followed by the raw source text of every string
  alternative in the same string literal that consists of more than one grapheme,
  joined with `|` in source order, followed by `|[...])`.


- Report each violating string alternative at the start of that alternative. For example, in `/[\q{abc}]/v`, report at line 1, column 6; in `/[\q{a|bc|}]/v`, report at line 1, column 8.
