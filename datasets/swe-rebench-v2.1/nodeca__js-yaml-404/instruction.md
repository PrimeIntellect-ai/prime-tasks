Incorrect dump of block scalar with leading newlines and spaces
The following code dumps invalid YAML:

```js
console.log(yaml.safeDump({ str: '\n    a\nb' }))
```

Invalid output due to indentation:

```yaml
str: |-

      a
  b
```

Leading spaces are handled in general by an indentation indicator (below), but leading newlines seem to thwart this (above):

```js
console.log(yaml.safeDump({ str: '    a\nb' }))
```

Valid output:

```yaml
str: |2-
      a
  b
```

The results above are from version 3.11.0.
