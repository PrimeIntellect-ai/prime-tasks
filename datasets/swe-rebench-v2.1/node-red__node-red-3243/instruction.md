Problem with context variables
### Current Behavior

When changing project the global context variables are kept for the new project.

### Expected Behavior

Delete the context variables from another project.

### Steps To Reproduce

1. Create a project.
2. Define global context variables.
3. Create another project.
4. Update the global context.

The context variables of the previous project are maintained.

### Example flow

```
paste your flow here
```


### Environment

- Node-RED version: 2.1.3
- Node.js version: v12.22.6
- npm version: 6.14.15
- Platform/OS: Rasperry Pi/Raspbian
- Browser: Chrome

### Additional contract requirements

- The context module (`@node-red/runtime/lib/nodes/context`) exposes a public method `delete(id, flowId?)` that returns a Promise. Calling `delete("global")` removes the global context from every configured store and re-creates it from the original `functionGlobalContext` seed. For a node or flow scope, the scoped data is deleted only when no external store is configured.
- The context module exposes a public method `clear()` that returns a Promise. Calling `clear()` removes all global and flow context scopes and re-creates the global context from the original `functionGlobalContext` seed.
- Switching the active project clears the context variables from the previous project. The runtime projects API (module `@node-red/runtime/lib/api/projects`, public name `@node-red/runtime_projects`) exposes `setActiveProject(opts)` where `opts` includes `user`, `id` and an optional `clearContext` flag; when `clearContext` is true the context of the previous project is cleared.
