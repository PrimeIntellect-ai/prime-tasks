Aliased name imports get wrongly converted
## Bug description

For further documentation i have to use export types in a certain way.
Due to this duplicate naming may occure and i have to rename types and interfaces when importing.
This results in imported zod schema not being aliased correctly, to import  and alias the resulting schemas.

### Input

```ts
// a.ts
export interface Obj {
    bug: "with aliased imports"
}
```

```ts
// b.ts
import { Obj as Renamed } from "./a.ts"

export interface Obj extends Renamed {
    should: "rename"
}
```

### Expected output

```ts
// a.ts
export const ObjSchema = z.object({
  bug: z.literal("with aliased imports")
})
```

```ts
import { ObjSchema as RenamedSchema } from "./a.ts"
// a.ts
export const ObjSchema= RenamedSchema.extend({
    should: z.literal("rename")
})
```

### Actual output

```ts
// a.ts
export const ObjSchema = z.object({
  bug: z.literal("with aliased imports")
})
```

```ts
import { RenamedSchema } from "./a.ts"
// a.ts
export const ObjSchema = RenamedSchema.extend({
    should: z.literal("rename")
})
```

**Versions**

- Typescript: `v5.6.3`
- Zod: `v3.23.8`
