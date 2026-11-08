FancyIndex doesn't encode square brackets
Paths that include square brackets ('[', ']') won't have those characters url encoded. As a consequence, many programs will fail to read from those URLs (e.g. VLCPlayer). If I url encode them myself, FancyIndex won't decode them and throw a 404.

### Additional contract requirements

- For a filename `bug[95].txt`, the generated href must be exactly `bug%5B95%5D.txt`.
- Requesting the bracket-containing filename with its brackets percent-encoded must retrieve the file successfully, not return a 404.
