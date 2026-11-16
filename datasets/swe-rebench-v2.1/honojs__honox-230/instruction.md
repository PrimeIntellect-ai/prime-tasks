Nested _middleware.ts is not being applied to nested folders
### What version of HonoX are you using?

0.1.23

### What steps can reproduce the bug?

Have a folder structure as below
/user
  _middleware.ts
    /todos

the _middleware in  inside `/user` folder, is not being applied to route `/user/todos` .

### What is the expected behavior?

`_middleware.ts` should apply to all nested child routes

### What do you see instead?

`_middleware` is being applied to current folder level route only.
When I move `_middleware.ts` to inside `/user/todos` it get apply to routes `/user/todos` correctly.

### Additional information

_No response_
_middleware.ts is not loaded for deeply nested param routes
### What version of HonoX are you using?

0.1.25

### What steps can reproduce the bug?

1. Add `_middleware.ts` with `console.log()` to `app/routes/organizations/[organizationId]/products/[productId]`
2. Add `index.tsx` to `app/routes/organizations/[organizationId]/products/[productId]`
3. Navigate to `/organizations/:organizationId/products/:productId` and see that the log is not shown

### What is the expected behavior?

Deeply nested param routes load the `_middleware.ts` file.

### What do you see instead?

`_middleware.ts` file is not loaded for deeply nested param routes.

### Additional information

This bug is related to https://github.com/honojs/honox/issues/184

[HIDDEN]

https://github.com/honojs/honox/blob/main/src/server/server.ts#L138
