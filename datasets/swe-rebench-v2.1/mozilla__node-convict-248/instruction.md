Allow the default / fallback parser to be specified
If a parser is not found for the extension of the file passed to `loadFile`, convict currently defaults to using the json5 parser (primarily for backwards compatibility). However, this can lead to cryptic errors that are hard to handle.

A better approach would be to allow a parser to be registered with the wildcard extension (i.e., `*`). This wildcard parser would then get used when no parser is registered for the extension of the given file.

By default, the json5 parser would be bound to the wildcard extension (again, for backwards compatibility). But this could be overridden, giving the application a hook to throw an error about an unsupported file type.

```js
convict.addParser({
  extension: '*',
  parse: () => { throw new Error("Unsupported file type") },
})
```
