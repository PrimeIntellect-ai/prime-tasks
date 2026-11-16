Auto update cache by default?
Hi!

Thanks for writing tealdeer, it's been great to use.

I've found having to manually update the cache to be confusing, especially on first-use. Consider the reference tldr package versus tealdeer:

```sh
❯ paru -S tldr
❯ tldr tldr

  Displays simple help pages for command-line tools, from the tldr-pages project.
  More information: <https://tldr.sh>.
```

```sh
❯ paru -S tealdeer
❯ tldr tldr
Warning: Cache not found. Please run `tldr --update`.
```

I had to dig throug the documentation and GitHub issues to find https://github.com/dbrgn/tealdeer/issues/90 and https://dbrgn.github.io/tealdeer/config_updates.html. At which point I had to seed the config:

```sh
❯ tldr --seed-config
```

Then enable auto cache update:

```diff
[updates]
-auto_update = false
+auto_update = true
auto_update_interval_hours = 720
```

Does it make sense to enable this behaviour by default?

### Additional contract requirements

- When the page cache is missing, stderr must contain the exact text "Page cache not found. Please run `tldr --update`".
