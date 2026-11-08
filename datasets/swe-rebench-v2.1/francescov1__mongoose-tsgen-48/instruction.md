Error when schema has a field of type Schema.Types.Buffer with a default of null
Hi, frist of all, thanks for this package. This is exactly what I wanted  since I don't want to touch my existing schema defs. :)

I think I found a bug related to Buffer in a schema:

Consider this

```
const homeSchema = new Schema(
  {
    id: String,
    image: {
     type: Schema.Types.Buffer,
     default: null
   }
});

```

For me. this throws an error during gen: `TypeError: Cannot read property 'required' of null` coming from here: https://github.com/francescov1/mongoose-tsgen/blob/854a1f9289bb07107622914bf8e76dbde202d2e5/src/helpers/parser.ts#L468

Now I don't know 100% if Buffer types even can have a default value null?

### Additional contract requirements

- Generating types for a schema that declares a field with `type: Schema.Types.Buffer` and `default: null` must complete without error.
- In the generated model, such a field must be an optional property typed as `Buffer` (the same Buffer type the generator already uses for other Buffer fields), so consuming code can read it as a `Buffer` or `undefined`. It must not be typed to include `null`.
