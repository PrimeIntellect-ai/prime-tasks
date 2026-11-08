filterProtocolClaims deletes properties required by the IdTokenClaims type
If filterProtocolClaims is set to true (the default), the properties `iss`, `aud`, `exp` and `iat` that are **_required_** by the IdTokenClaims type are deleted and undefined, thus breaking the defined types.

```typescript
const userManager = new UserManager({
  // ... other options omitted
  filterProtocolClaims: true, // defaults to true
  // ...
});
const user = await userManager.getUser();
const exp = user.profile.exp; // TypeScript says this is a number
console.log(typeof exp) // Should be "number" but is "undefined"
```

**Relevant parts of the code**

These properties are deleted from the response:
https://github.com/authts/oidc-client-ts/blob/bcfe363c685e8f243b43bc588ecba7495f88ffa9/src/ResponseValidator.ts#L26-L41
https://github.com/authts/oidc-client-ts/blob/bcfe363c685e8f243b43bc588ecba7495f88ffa9/src/ResponseValidator.ts#L225-L235
Some of which are mandatory here:
https://github.com/authts/oidc-client-ts/blob/bcfe363c685e8f243b43bc588ecba7495f88ffa9/src/Claims.ts#L109
