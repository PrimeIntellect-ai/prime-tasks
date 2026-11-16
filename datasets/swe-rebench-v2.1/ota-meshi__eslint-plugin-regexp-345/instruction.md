Suggest `i` flag if it simplifies the pattern
If a pattern can be simplified by adding the `i` flag (e.g. `/[a-fA-F]/` -> `/[a-f]/i`), it might be a good idea to suggest that to the user.

The conditions for this rule to add the `i` flag (and subsequently simplify the pattern) are:

1. The `i` flag isn't present.
2. All characters, character classes, and character sets match the same character(s) regardless of the `i` flag (aka. the flag doesn't change the meaning of the pattern.)
3. There is at least one character class that can be simplified because of the added `i` flag. E.g. a character range can be removed, or a character class can be replaced by a character or character set, or similar.

### Additional contract requirements

- Expose and register this behavior as the ESLint rule `use-ignore-case`.
- The rule reports one diagnostic per regular expression that can be simplified. The diagnostic message is exactly:

  ```
  The character class(es) <classes> can be simplified using the `i` flag.
  ```

  Here, `<classes>` is the comma-and-space separated list of the source texts of the character classes that can be simplified, each enclosed in single quotes (for example `'[a-zA-Z]'` or `'[xX]', '[a-fA-F0-9]'`).
- The auto-fix removes the redundant character-class elements and appends the `i` flag. For the patterns below the fix produces exactly:
  - `/[a-zA-Z]/` -> `/[a-z]/i`
  - `/\b0[xX][a-fA-F0-9]+\b/` -> `/\b0[x][a-f0-9]+\b/i`
  - `RegExp("[a-zA-Z]")` -> `RegExp("[a-z]", "i")`
