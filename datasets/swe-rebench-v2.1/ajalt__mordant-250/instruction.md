Selected value for interactiveSelectList
`Terminal.interactiveSelectList()` returns the visible title of the selected entry. This is not always convenient. It would be useful to specify a (hidden) value in each entry which is returned instead of the title (a bit like HTML &lt;option value="..."&gt;).

This could be added to `SelectList.Entry`:

```kotlin
    data class Entry(
        /** The title of the entry. */
        val title: String,
        /** An optional description of the entry. */
        val description: Widget? = null,
        /** Whether this entry is marked as selected. */
        val selected: Boolean = false,
        /** Return this value instead of title if not null. */
        val value: String? = null,
       )
```

### Additional contract requirements

- `Terminal.interactiveMultiSelectList(entries: List<SelectList.Entry>)` returns a list containing, for each selected entry, its hidden `value` when one is set and otherwise that entry's title.
- `SelectList.Entry` (in `com.github.ajalt.mordant.widgets`) also provides a convenience constructor `SelectList.Entry(title: String, description: String?, selected: Boolean = false, value: String? = null)` that accepts the description as a plain `String` and still supports the optional hidden `value`.
