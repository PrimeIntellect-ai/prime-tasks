If changes to `.po` file are discarded (accidentally), they're not added back
### How to reproduce:

https://github.com/saveman71/gettext-repro-cases/tree/missing-po-if-checked-out

In `gettext_mwe.ex`, add a second `gettext` call to the `gettext` function:

```elixir
  gettext("First string")
  gettext("Second string")
```

Run `mix gettext.extract --merge` and observe that both `po` and `pot` files are updated.

Run `git checkout -- priv/gettext/fr/LC_MESSAGES/default.po` to "accidentally" reset the `po` file.

Run `mix gettext.extract --merge` and observe that nothing is updated.

From that point on, if you commit and push, gettext won't catch the new strings until the code is modified.

### Expected behaviour

If you change/discard the changes to `default.pot`, gettext will overwrite your changes based on what's found.
I expect the same thing if I change/discard changes in `default.po`.
