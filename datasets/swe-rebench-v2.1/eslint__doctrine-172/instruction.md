Support string/numeric/boolean literal types
JSDoc supports, e.g.:

```
/**
 * @typedef {Object} Comment
 * @property {('public'|'protected'|'private')} access
 */
```

`jsdoc -X` output looks like:

```
...
        "properties": [
            {
                "type": {
                    "names": [
                        "'public'",
                        "'protected'",
                        "'private'"
                    ]
                },
                "name": "access"
            }
        ],
...
```

This is useful to support enumerated types. See, for instance, https://github.com/jsdoc3/jsdoc/issues/629, https://github.com/jsdoc3/jsdoc/issues/1065, and https://github.com/documentationjs/documentation/issues/373.
