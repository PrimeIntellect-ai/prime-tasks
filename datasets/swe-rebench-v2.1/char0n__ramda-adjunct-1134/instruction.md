trimStart/trimEnd
https://github.com/tc39/proposal-string-left-right-trim

Don't forget appropriate polyfills + aliases (https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/trimStart)

### Additional contract requirements

- Provide a `trimEnd` operation that removes trailing whitespace while preserving the rest of the string.
- Keep `trimEnd` usable when the native string-trimming method is unavailable by providing appropriate polyfill behavior.
- Export `trimRight` as an alias for `trimEnd`.
