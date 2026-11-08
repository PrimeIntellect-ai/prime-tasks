Add ability to allow error props only for specific errors.
Below is shown a common pattern for creating custom error objects.

**Problem:** `allowErrorProps` applies to **all** errors which could be a security issue if another error has sensitive data in the prop that you have allowed.

**Suggestion:** Add ability to allow props with the `registerClass` function:

```ts
SuperJson.registerClass(UsernameTakenError, {allowProps: ['suggestedUserName']})
```

```ts
import SuperJson from "superjson")

export class UsernameTakenError extends Error {
  name = "UsernameTakenError"
  constructor({suggestedUserName}) {
    super()
    this.suggestedUserName = suggestedUserName
  }
}
// Register with SuperJson serializer so it's reconstructed on the client
SuperJson.registerClass(UsernameTakenError)
SuperJson.allowErrorProps("suggestedUserName")
```

### Additional contract requirements

When an Error subclass is registered with `registerClass` and an `allowProps` list, only the listed custom properties are serialized for instances of that class. The allowlist is specific to that registered error class: it does not cause those properties to be serialized for other errors.
