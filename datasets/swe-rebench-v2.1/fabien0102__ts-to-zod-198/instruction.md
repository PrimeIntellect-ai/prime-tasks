Nullable with Parenthesis is Ignored
## Bug description

Nullable parenthesis is not working

### Input

```ts
export interface Root {
  id: number;
}

export interface NameProps {
  name: string;
}

export interface NumProps {
  num: number;
}

export type Dem = (Root & NameProps & NumProps) | null;

export type Dom = ("a" | "b") | null;

```

### Expected output

```ts
import { z } from "zod";

export const rootSchema = z.object({
  id: z.number(),
});

export const namePropsSchema = z.object({
  name: z.string(),
});

export const numPropsSchema = z.object({
  num: z.number(),
});

export const demSchema = rootSchema
  .and(namePropsSchema)
  .and(numPropsSchema)
  .nullable();

export const domSchema = z.union([z.literal("a"), z.literal("b")]).nullable();


```

### Actual output

```ts
import { z } from "zod";

export const rootSchema = z.object({
  id: z.number(),
});

export const namePropsSchema = z.object({
  name: z.string(),
});

export const numPropsSchema = z.object({
  num: z.number(),
});

export const demSchema = rootSchema.and(namePropsSchema).and(numPropsSchema);

export const domSchema = z.union([z.literal("a"), z.literal("b")]);

```

**Versions**

- Typescript: `v5.2.2`
- Zod: `v3.6.0`

### Additional contract requirements

A parenthesized type followed by `| null` must produce a schema with `.nullable()`, including when the parenthesized type is a single literal type.
