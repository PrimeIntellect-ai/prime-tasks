can-zone adds cycle to errors
```js
error = {
    message: ...
    errors: [ error ]
    ...
}
```

This cycle will cause problems downstream if any tool tries to serialize the error,  see https://github.com/stealjs/steal/issues/1509 for more details.
