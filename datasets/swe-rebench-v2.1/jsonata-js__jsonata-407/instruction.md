Transform error with null values
Hello,
I believe this is an error:

Input:

```json
{
  "hi": "world",
  "bye": null
}
```

Transform:

```js
$ ~> | ** ["hi"] | {"hello": hi}, ["hi"] |
```

Output with http://try.jsonata.org :

```
u is null
```

Instead, I would expect the following output:

```json
{
  "bye": null,
  "hello": "world"
}
```
