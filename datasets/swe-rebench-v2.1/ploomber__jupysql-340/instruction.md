update .md headers
in the doc folder, we have many .md files and they all contain metadata that looks like this:

```yaml
---
jupytext:
  notebook_metadata_filter: myst
  text_representation:
    extension: .md
    format_name: myst
    format_version: 0.13
    jupytext_version: 1.14.4
kernelspec:
  display_name: Python 3 (ipykernel)
  language: python
  name: python3
---
```

however, some of them are missing the `notebook_metadata_filter: myst`, which causes jupyter to delete certain parts of the metadata, we need to ensure `notebook_metadata_filter: myst` is in all .md files in the doc folder

### Additional contract requirements

- Every `.md` file in the `doc` folder that starts with a YAML metadata block (a `---` front matter section) must contain `notebook_metadata_filter: myst` inside that metadata block.
