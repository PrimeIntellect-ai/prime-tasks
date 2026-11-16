export interfaces on defineXFactory
First of all, really like the look of this library. Hoping to switch to it from our current solution.

However having an issue with creating reusable factory templates and exporting them (e.g. for overriding defaults across several different test files). For example:

```Typescript
export const factory = defineUserFactory({
  defaultData: async () => ({
    displayName: faker.name.fullName().slice(0, 30),
    email: faker.internet.email().slice(0, 100),
  }),
});
```

Current fails to compile with `Exported variable 'factory' has or is using name 'UserFactoryInterface' from external module "<dir>/src/factories/__generated__/fabbrica/index" but cannot be named.`. This would be solvable by being able to import `UserFactoryInterface`, however the generated factories don't export these interfaces.

Is it possible to either:
- Export the related interfaces for each `defineXFactory`, so they can be imported into another file?
- For me to do this in a better way that doesn't require that above?

Thanks for your time!

### Additional contract requirements

- The generated module must export each factory interface under its exact name (for example `UserFactoryInterface`) so that it can be imported from another file. The generated TypeScript must declare the interface with the `export` modifier, i.e. it must be emitted as `export interface UserFactoryInterface { ... }`.
