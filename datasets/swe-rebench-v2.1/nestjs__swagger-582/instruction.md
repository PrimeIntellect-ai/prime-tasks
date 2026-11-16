Invalid specification for nested schema with additional properties
<!--
PLEASE HELP US PROCESS GITHUB ISSUES FASTER BY PROVIDING THE FOLLOWING INFORMATION.

ISSUES MISSING IMPORTANT INFORMATION MAY BE CLOSED WITHOUT INVESTIGATION.
-->

## I'm submitting a...
<!--
Please search GitHub for a similar issue or PR before submitting.
Check one of the following options with "x" -->
<pre><code>
[x] Regression <!--(a behavior that used to work and stopped working in a new release)-->
[x] Bug report
[ ] Feature request
[ ] Documentation issue or request
[ ] Support request => Please do not submit support request here, instead post your question on Stack Overflow.
</code></pre>

## Current behavior
<!-- Describe how the issue manifests. -->

When using a nested object in a Swagger schema, additional properties (e.g. `description`) are not properly added to the schema. They are not visible in the Swagger UI.

Generated Schema (extract from Specification):

```json5
// components.schemas:
{
  "NestedProperty": {
    "type": "object",
    "properties": {}
  },
  "NestedObjectDto": {
    "type": "object",
    "properties": {
      "foo": {
        "description": "Foo Bar", // <--- $ref does not allow any other properties
        "$ref": "#/components/schemas/NestedProperty"
      }
    },
    "required": ["foo"]
  }
}
```

## Expected behavior
<!-- Describe what the desired behavior would be. -->

Additional properties should be merged with the referenced schema using `allOf`. This was already the case in `@nestjs/swagger@3`.

The generated schema should look like this:

```json5
// components.schemas:
{
  "NestedProperty": {
    "type": "object",
    "properties": {}
  },
  "NestedObjectDto": {
    "type": "object",
    "properties": {
      "foo": {
        "allOf": [ // <- Using allOf to merge $ref with additional props
          { "description": "Foo Bar" },
          { "$ref": "#/components/schemas/NestedProperty" }
        ]
      }
    },
    "required": ["foo"]
  }
}
```

## Minimal reproduction of the problem with instructions
<!-- Please share a repo, a gist, or step-by-step instructions. -->

1. Create a new Nestjs App
2. Install swagger integration according to docs
3. Add this dto:

```typescript
import { ApiProperty } from '@nestjs/swagger';

class NestedProperty {}

export class NestedObjectDto {
  @ApiProperty({ description: 'Foo Bar', type: NestedProperty })
  foo: NestedProperty;
}
```

4. Change default `AppController#getHello` to use the DTO:

```diff
  @Get()
- getHello(): string {
+ getHello(@Body() body: NestedObjectDto): string {
    return this.appService.getHello();
  }
```
5. Check Swagger UI for missing description

## What is the motivation / use case for changing the behavior?
<!-- Describe the motivation or the concrete use case. -->
I want to add additional properties to nested schema objects (`description`, `nullable`, etc.).

## Environment

<pre><code>
Nest version: 6.11.5
<!-- Check whether this is still an issue in the most recent Nest version -->

For Tooling issues:
- Node version: v12.13.0
- Platform:  Linux
Others:
- @nestjs/swagger: 4.2.6

</code></pre>

### Additional contract requirements

- For a property declared with `@ApiProperty({ description: 'Foo Bar', type: NestedProperty })`, represent the referenced schema and additional property metadata together using `allOf`.
- The additional metadata object MUST carry every extra option supplied to `@ApiProperty` (for example, `description` and `nullable`), not just `description`.
