Language tag is not read from .po header
When you read in a .po file that already has the "Language" header specified, writing it out again will erase the Language header. I sent pull request #420 to fix this.

### Additional contract requirements

- When `read_po` is called with `locale='de'` and the .po header contains `Language: en_US`, `catalog.locale` must be `Locale('en', 'US')`.
