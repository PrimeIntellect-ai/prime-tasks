Bug: regex problem
In Custeom Regex Replacement section I'm trying to convert HTML links to markdown links with that regex:

find: `<a.*?href=["']([^"']*)["'][^>]*>([^<]*)<\/a>` `igm` `[$2]($1)`

Generally it works, but sometimes it fails, for example in this case:

```
Wycinek utworzono z: <a href="https://www.tygodnikpowszechny.pl/zycie-pod-mikroskopem-151274" class="tc-tiddlylink-external" rel="noopener noreferrer" target="_blank">https://www.tygodnikpowszechny.pl/zycie-pod-mikroskopem-151274</a>
```
the link is converted to:

```
Wycinek utworzono z: <a href="https://www.tygodnikpowszechny.pl/zycie-pod-mikroskopem-151274" class="tc-tiddlylink-external" rel="noopener noreferrer" target="_blank"><https://www.tygodnikpowszechny.pl/zycie-pod-mikroskopem-151274</a>>
```

When testing in [https://regexr.com/](https://regexr.com/), my regex works fine.

### Additional contract requirements

- Applying the custom regex replacement `find: <a.*?href=["']([^"']*)["'][^>]*>([^<]*)<\/a>`, `flags: igm`, `replace: [$2]($1)` to the example above must produce:

  ```
  Wycinek utworzono z: [https://www.tygodnikpowszechny.pl/zycie-pod-mikroskopem-151274](https://www.tygodnikpowszechny.pl/zycie-pod-mikroskopem-151274)
  ```

- The `No Bare URLs` rule must leave HTML anchor tags (`<a ...>...</a>`) unchanged.
