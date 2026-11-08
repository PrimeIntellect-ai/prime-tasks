Apply formatting on enter
We should also apply formatting on enter, not just on space.

### Additional contract requirements

- The package exposes a public modifier `changeCurrentInlineStyle(editorState, matchArr, style, character)` in `src/modifiers/changeCurrentInlineStyle.js`. It replaces the matched markdown text with its unwrapped content, applies `style` to that range, and inserts `character` at the caret position. When `character` is omitted, a single space is inserted.
- The markdown plugin is created by the package's default export `createMarkdownPlugin`.
- The plugin exposes a public return handler `handleReturn(ev, editorState, { setEditorState })`. When the user presses Enter, this handler must apply inline markdown formatting (for example, converting `` `code` `` into code-styled text) and report the event as handled, just as the plugin already does when the user types a space.
