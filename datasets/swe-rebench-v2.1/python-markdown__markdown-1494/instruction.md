toc: Unusual characters in heading ids not well supported
I noticed that `toc` encodes characters like `*` as `\x0242\x03`, 42 being the index of `*` in the ASCII table. This causes a discrepancy between the permalink of a heading and the link in the table of contents.

```bash
mkdir /tmp/toc
cd /tmp/toc
python -m venv .venv
. .venv/bin/activate
python -m pip install mkdocs
python -m mkdocs new .
```

index file:

```md
# Welcome

Demonstrating an issue with HTML ids and `toc`.

## `*Foo*` { id="\*Foo\*" }

- Click on `*Foo*`'s permalink: `#*Foo*` in the URL.
- Click on `*Foo*` in the table of contents: `#%0242%03Foo%0242%03` in the URL.
```

mkdocs config:

```yaml
site_name: My Docs

markdown_extensions:
- attr_list
- toc:
    permalink: true
```

Serve and observe the behavior described in the index page.

I'm not saying this is a bug. I'm just curious if this is expected, and whether there would be a way improve support for headings with such "unusual" ids. This would help for the work I'm doing with mkdocstrings, where we try to expand our languages support, and some languages might use uncommon characters in object identifiers. Not only `toc` would have to work, but also mkdocs-autorefs, which picks up ids from the table of contents when registering URLs and anchors to objects.

I believe HTML5 supports any kind of characters in ids. Some of them just cause a bit of pain, like `.` or `#`, because they then need to be escaped in CSS selectors.

### Additional contract requirements

- The `toc` extension exposes the generated table of contents on the `Markdown` instance as `toc_tokens`: a list of dictionaries, one per included heading, each containing the keys `level`, `id`, `name`, `html`, `data-toc-label`, and `children`.
- The `id` value in each `toc_tokens` entry is the heading's id with backslash escapes removed. For a heading whose id is set through `attr_list` as `{ id="\*Foo\*" }`, the entry's `id` is `*Foo*`, matching the id rendered on the heading element.
- The remaining `toc_tokens` keys (`level`, `name`, `html`, `data-toc-label`, `children`) keep the values they already have.
- The link in the rendered table of contents (available as the `toc` attribute on the `Markdown` instance) resolves to the same fragment as the heading's id.
