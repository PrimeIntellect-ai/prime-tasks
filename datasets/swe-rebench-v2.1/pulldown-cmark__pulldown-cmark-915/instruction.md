Support for Description Lists
Some parsers have an extension to support description/definition lists. In https://talk.commonmark.org/t/description-list/289 there is a proposal to add it to CommonMark. A common syntax is to put a colon at the beginning of the line.

An example from the [Pandoc manual](http://pandoc.org/MANUAL.html#definition-lists):

```
Term 1

:   Definition 1

Term 2 with *inline markup*

:   Definition 2

        { some code, part of Definition 2 }

    Third paragraph of definition 2.
```

### Additional contract requirements

- Add a public flag `Options::ENABLE_DEFINITION_LIST` to the `Options` bitflags type in the `pulldown_cmark` crate. Inserting it into an `Options` set (for example `opts.insert(Options::ENABLE_DEFINITION_LIST)`) enables the CommonMark-HS-compatible definition-list extension, so the parser recognizes `:` markers and the HTML writer emits `<dl>`, `<dt>`, and `<dd>` elements.
- For the input `apple\n:   red fruit\n\norange\n:   orange fruit\n`, the HTML output must be exactly `<dl>\n<dt>apple</dt>\n<dd>red fruit</dd>\n<dt>orange</dt>\n<dd>orange fruit</dd>\n</dl>\n`.
