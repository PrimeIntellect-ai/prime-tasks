Customize field names without alias
**Is your feature request related to a problem? Please describe.**
By default ugly names will be generated if the field name contains an underscore. This can be worked around using aliases as [documented](https://github.com/Khan/genqlient/blob/main/docs/operations.md#field-names), but this has limitations. If the server operator has configured [max aliases](https://escape.tech/graphql-armor/docs/plugins/max-aliases/), queries will fail when they exceed this.

**Describe the solution you'd like**
The ability to customize the field names using a `@genqlient` directive as an alternative to aliases.

### Additional contract requirements

A field may use `@genqlient(alias: "<name>")` to choose the generated Go response field name. This changes the Go field name only: the GraphQL operation retains the original field name and does not add a GraphQL alias.
