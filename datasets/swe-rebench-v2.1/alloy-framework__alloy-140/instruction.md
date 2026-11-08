readonly attribute ignored for indexer InterfaceMember
```ts
   <ts.InterfaceMember
          readonly
          indexer="key: string"
          type="unknwown"
        />
```

produce
```ts
  [key: string]: unknown;
```

### Additional contract requirements

- The unprefixed output shown after “produce” in the base is the faulty behavior, not the intended result. The `readonly` prop must be honored for indexer members: `<ts.InterfaceMember readonly indexer="key: string" type="unknown" />` produces `readonly [key: string]: unknown;`.
- When `readonly` is not set, an indexer member is rendered without the `readonly` prefix, e.g. `<ts.InterfaceMember indexer="str: string" type="number" />` produces `[str: string]: number;`.
