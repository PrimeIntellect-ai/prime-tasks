Default `preferLocal` to `true` when using `$`
The default value for [`preferLocal`](https://github.com/sindresorhus/execa#preferlocal) used to be `true`. We changed it to `false` in #314 because it conflicted with some uncommon setups (#196, #153). IMHO `preferLocal` is still a very helpful option for most users, and it's too bad we cannot enable it by default due to the above.

Now, I am wondering whether the default value should be `true` with the new `$` methods we just introduced? The reasons for this is:
  - It is easier for users with the uncommon setups mentioned above to change the default value thanks to the options binding method: `const $$ = $({ preferLocal: false })`
  - `$()` is more likely than `execa()` to be used in a script with many commands to execute. This increases the chance of at least one of them to be a local binary.

What do you think @sindresorhus and @aaronccasanova?

### Additional contract requirements

- The `$` helper defaults `preferLocal` to `true` for both asynchronous and synchronous command execution.
- A caller may bind `preferLocal: false` to `$` to disable local binary preference for both forms.
- This default is specific to `$`; direct `execa()` calls retain their existing default of `false`.
