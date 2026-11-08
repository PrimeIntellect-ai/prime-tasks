Lines wrap incorrectly when followed by a non-wrappable line
Hello! I believe I've found a bug. I have a markdown file `untitled.md`:

```md
item that doesn't need wrapping

a-long-line-that-won't-be-wrapped-because-there-is-no-character-it-can-break-on
```

When running this through the cli with the `--to commonmark` and `--width 72` options:

```sh
comrak --to commonmark --width 72 untitled.md
```

It outputs the following:

```md
item that doesn't need
wrapping

a-long-line-that-won't-be-wrapped-because-there-is-no-character-it-can-break-on
```

I think the list item is not supposed to wrap there. If the last line is short enough to not need wrapping, this doesn't occur. If the last line is wrappable (e.g. remove all the `-` characters), this also doesn't occur.
