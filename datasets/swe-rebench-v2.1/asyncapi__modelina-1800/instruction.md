Support verbatimModuleSyntax in TypeScript Generator
#### Reason/Context
Currently the typescript generator does not explicitly export/import interfaces as types. This is an issue when the typescript option 'verbatimModuleSyntax' is enabled and can potentially cause some other pitfalls.


#### Description
Add a new flag (or make this the default behaviour when using interfaces, afaik that should not cause any issues) that changes the behaviour of 'src/generators/typescript/TypeScriptDependencyManager.ts' so it imports and exports interfaces as types.

Before:
```typescript
import { PublicUser } from './PublicUser'
interface NewStatePayload {
  members: PublicUser[]
}
export { NewStatePayload }
```
After:
```typescript
import type { PublicUser } from './PublicUser'
interface NewStatePayload {
  members: PublicUser[]
}
export type { NewStatePayload }
```

### Additional contract requirements

For ESM models rendered as interfaces with named exports, imports of model dependencies and named exports must be type-only. This behaviour may be enabled by default or through the `useTypeOnlyImportsAndExports` generator option; when that option is provided as `true`, the type-only behavior must be enabled.
