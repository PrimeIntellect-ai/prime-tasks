TOC: Configurable permalink title attribute
Would be nice to have an ability to set a custom title text for permalink title attribute. For example:

```yml
- toc:
    title: 'Ссылка на этот раздел' #Custom title here
    permalink: '#'
    slugify: !!python/name:pymdownx.slugs.uslugify
```

For now, "Permament link" text is simply hardcoded within `toc.py`:
https://github.com/Python-Markdown/markdown/blob/9ec83c4c414f27bc8aa490dbac1fe30b49058ae6/markdown/extensions/toc.py#L194

Related: #657

### Additional contract requirements

- The TOC extension can be configured with `permalink_title` to set the `title` attribute text on generated permalinks.
- If no custom permalink title is configured, generated permalinks retain the default title `Permanent link`.
