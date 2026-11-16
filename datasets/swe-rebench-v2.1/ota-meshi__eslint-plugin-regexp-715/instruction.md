Change default configuration of `prefer-d`
I just added `eslint-plugin-regexp` to a code base with some regexes and [the `prefer-d` rule](https://ota-meshi.github.io/eslint-plugin-regexp/rules/prefer-d.html) wanted to replace all character classes like this `[0-9a-f]` with this `[\da-f]`. While I think that `prefer-d` has a place in our `recommended` config, but I think it's too aggressive by default. `[0-9a-f]` -> `[\da-f]` is a minor stylistic change to enforce consistency, but it will increase the diff for existing code bases and it won't improve the readability. Since `0-9` is relatively common from what I've seen, `prefer-d` currently causes a lot of noise for little gain.

So I think it might be a good idea to change the default configuration of `prefer-d` from `insideCharacterClass: "d"` to `insideCharacterClass: "ignore"`. This would still transform `[0-9]` -> `\d` but it will leave `[0-9a-f]` and `[\da-f]` as is.

With this change, `prefer-d` will report strictly fewer errors, so this is a minor change according to ESLint's semver policy.

What do you think @ota-meshi?
