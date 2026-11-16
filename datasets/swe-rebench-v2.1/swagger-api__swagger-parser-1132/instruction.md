Examples with Ref not parsed when in request bodies
The same as #837, but for request bodies.

```yaml
requestBody:
  content:
    application/json:
      examples:
         key:
           $ref: 'file.yaml#components/examples/key'
```
