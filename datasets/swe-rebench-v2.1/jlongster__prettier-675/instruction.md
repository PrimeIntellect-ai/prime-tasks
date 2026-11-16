Strange formatting for "if" with comment on the same line
Input:
```js
// Accept empty response
if (response.clone) { // for fetch api

} else { // for xhr

}
```

Output:
```js
// Accept empty response
if (
  response.clone // for fetch api
) {
} else { // for xhr
}
```

https://jlongster.github.io/prettier/#%7B%22content%22%3A%22%2F%2F%20Accept%20empty%20response%5Cnif%20(response.clone)%20%7B%20%2F%2F%20for%20fetch%20api%5Cn%5Cn%7D%20else%20%7B%20%2F%2F%20for%20xhr%5Cn%5Cn%7D%22%2C%22options%22%3A%7B%22printWidth%22%3A80%2C%22tabWidth%22%3A2%2C%22singleQuote%22%3Afalse%2C%22trailingComma%22%3Afalse%2C%22bracketSpacing%22%3Atrue%2C%22doc%22%3Afalse%7D%7D

### Additional contract requirements

A comment that is not attached to any node (a "dangling" comment) is printed on its own line, indented, rather than on the same line as the surrounding punctuation. This applies to dangling comments in block statements, object literals, array literals, and class bodies. In a JSX empty expression, a dangling comment is printed inline between the braces.
