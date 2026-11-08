Support publishing markdown descriptions to Warehouse
PEP 566 is now implemented in Warehouse:
https://dustingram.com/articles/2018/03/16/markdown-descriptions-on-pypi

### Additional contract requirements

- When a package's long description is written in Markdown, the published metadata must include `Description-Content-Type: text/markdown`, so that Warehouse renders it as Markdown.
- The Markdown description must be published as written, without being converted to another format.
