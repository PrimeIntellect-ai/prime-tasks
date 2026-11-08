Error when referencing an imported type in an Index Signature Type
## Feature description

<!-- A clear and concise description of what the feature could be. -->
To support index signature type.

### Input

```ts
// typescript type or interface causing the output
export interface ResourceLink {
    /**
     * The link url.
     * @type {string}
     * @memberof ResourceLink
     */
    href: string;
    /**
     * The link method.
     * @type {string}
     * @memberof ResourceLink
     */
    method: string;
    /**
     * Additional data about the link.
     * @type {string}
     * @memberof ResourceLink
     */
    metadata?: string | null;
}

export interface AppDto {
    /**
     * The links.
     * @type {{ [key: string]: ResourceLink; }}
     * @memberof AppDto
     */
    links: {
        [key: string]: ResourceLink;
    };
}
```

### Output

```ts
// Expected Zod schemas
export const resourceLinkSchema = z.object({
  href: z.string(),
  method: z.string(),
  metadata: z.string().optional().nullable(),
});

export const appDtoSchema = z.object({
  links: z.record(resourceLinkSchema),
});
```
