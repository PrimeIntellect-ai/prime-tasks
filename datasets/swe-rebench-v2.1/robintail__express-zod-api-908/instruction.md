`z.record(z.any())` generates invalid OpenAPI spec
Hi, I've run into some trouble with OpenAPI spec generation of input and output payloads. My goal is to accept an arbitrary object as input. The way I've found that I can accomplish this is with `z.record(z.any())` and that works just fine functionality wise. The issue I run into is that when I generate the docs, I get the following YAML in the OpenAPI spec that's generated:

```yaml
type: object
additionalProperties:
  format: any
  nullable: true
```

When I check the validity of this using a tool like Redocly's CLI, I get the following error:

```
The `type` field must be defined when the `nullable` field is used.

687 |   additionalProperties:
688 |     format: any
689 |     nullable: true
```

From looking at the OpenAPI spec, this is an accurate error. I was wondering if there was a known workaround/better way to handle a schema field for accepting an arbitrary object. Just using `z.any()` results in the same error as above.

If I manually edit the spec and add `type: object` to the `additionalProperties`, the spec stops throwing that error. Here's an example:

```
type: object
additionalProperties:
  format: any
  nullable: true
  type: object
```

I'm wondering if this is an issue with spec generation, or if I'm just trying to tackle this problem the wrong way. If you have any advice on how I should be using Zod to accept an arbitrary object that passes the OpenAPI spec, I'd love to hear.

Thank you!

### Additional contract requirements

- In generated OpenAPI depictions of `z.any()` and `z.preprocess()` schemas whose depiction has no `type` property, omit `nullable: true`. For `z.record(z.any())`, `additionalProperties` must be `{ "format": "any" }`, without `type` or `nullable`.
