Default field label should be its parent object key property
```js
{
  type: "object",
  properties: {
    firstName: {type: "string"}
  }
}
```

The firstName field should have its label automatically set to `firstName` by default.

### Additional contract requirements

- When a schema property defines a `title`, use that title as its label instead of the property key.
- For any property type, when a schema property has no `title`, use its property key as its rendered label.
- These label rules apply regardless of the property's type.
