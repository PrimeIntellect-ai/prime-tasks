Support one column vs multi-column view for Board query display
~Currently only possible to configure in the UI~

Unblocked with the recent addition of the `column_layout` field in the Boards API. Defaults to `multi` but `single` is also possible

### Additional contract requirements

- The board resource exposes an optional, computed string attribute named `column_layout`. It accepts the values `multi` (the default) and `single`.
- A `list` style board must not specify a column layout. Configuring a `list` style board together with a `column_layout` value must fail with the error message `list style boards cannot specify a column layout`.
- The client package defines a public string type `BoardColumnStyle` with the public constants `BoardColumnStyleMulti` (value `"multi"`) and `BoardColumnStyleSingle` (value `"single"`).
- The client `Board` model exposes a public field `ColumnLayout` of type `BoardColumnStyle`, serialized as `column_layout`.
