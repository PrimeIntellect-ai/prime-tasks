Configurable interpolation syntax
**Is your feature request related to a problem? Please describe.**
Currently interpolation uses `${` and `}` as delimiters. The problem is that a possible use case for Nickel is Nixpkgs, where the content of strings is often Bash scripts. Bash variables can be of the form `${VAR}`, so the interpolation syntax clashes.

**Describe the solution you'd like**
In https://github.com/tweag/nickel/pull/197#issuecomment-726815882, @edolstra puts forward the idea of using the outward delimiters of a multi-line string to determine what the interpolation syntax inside it should be.

**Describe alternatives you've considered**
Alternatives would be to say always use `#{`, `}`. There is precedent for that syntax in Ruby, and it doesn't clash with Bash. However, whichever syntax we choose, it's going to clash with _something_. So making it locally configurable like @edolstra suggests is a neatly general solution.

### Additional contract requirements

- In ordinary quoted strings, Nickel interpolation starts with `#{` and ends with `}`. Shell-style `${VAR}` text remains literal and does not start Nickel interpolation.
- In a multiline string, the number of `#` characters in its opening delimiter determines the interpolation opener: that same number of hashes followed by `{` starts interpolation. A different number of hashes followed by `{` is literal string content.
