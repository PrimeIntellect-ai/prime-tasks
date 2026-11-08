`regexp/prefer-d`: Add an option for whole `\d`s
**Description**
I think that the range `0-9` can be more readable than `\d` in some situations. E.g. `[0-9a-f]` vs `[\da-f]`.

I think we should an option that makes it so that only whole character classes that are equal to `\d` or `\D` are reported. So `[0-9]` will be reported but `[0-9a-f]` won't.

What do you think @ota-meshi?

### Additional contract requirements

The `prefer-d` rule supports the option `insideCharacterClass: "ignore"`. With this setting, it reports character classes equivalent as a whole to `\d` or `\D`, but does not report a digit set when it appears only as an element of a larger character class.
