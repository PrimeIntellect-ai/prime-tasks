Typo in Borders member TOP_BOTTOM (TOM_BOTTOM)
In the `com.github.ajalt.mordant.table.Borders` enum, the member for a top-and-bottom border is called `TOM_BOTTOM` instead of `TOP_BOTTOM`. [Source code](https://github.com/ajalt/mordant/blob/3a344a7ce17e312684e68beb539cb5fe557242d8/mordant/src/commonMain/kotlin/com/github/ajalt/mordant/table/Borders.kt#L14).

### Additional contract requirements

- The `com.github.ajalt.mordant.table.Borders` enum must expose a member named `TOP_BOTTOM` whose `top` and `bottom` flags are `true` and whose `left` and `right` flags are `false`.
- The legacy member name `TOM_BOTTOM` must remain available on the `com.github.ajalt.mordant.table.Borders` enum as an alias with the same flags as `TOP_BOTTOM`.
