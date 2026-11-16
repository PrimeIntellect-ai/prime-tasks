make <Table> content selectable for copy and paste
## Description

in the `<Table>` you currently can't copy  the content. It would be better if the table can do this.

## Context

you often need to copy some content from a table (money amounts etc)

## Consequences

problem: in react-aria tables are also not for copy content.

### Additional contract requirements

- `<Table>` accepts a `selectionMode` prop with the values `'none' | 'single' | 'multiple'`, defaulting to `'none'`. A table is interactive when `selectionMode` is `'single'` or `'multiple'`, and non-interactive when it is `'none'`.
- `<Table>` accepts a `disabledKeys` prop listing the keys of rows that are disabled.
- Rows of a non-interactive table render with `cursor: text`.
- In an interactive table, enabled rows render with `cursor: pointer` and disabled rows render with `cursor: default`.
- In a non-interactive table, cell content can be selected and copied.
