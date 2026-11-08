Limit `nodeModulesWithDynamicImports` to unresolved dynamic imports
**- What is the current behavior?**

When bundling Node functions with esbuild, zip-it-and-ship-it will return a `nodeModulesWithDynamicImports` property, which contains a list of modules that make use of `require`/`import` statements with dynamic expressions. This allows consumers such as Netlify Build to warn users of potential issues and suggest workarounds.

_Example:_

```
4:41:05 PM: ❯ The following Node.js modules use dynamic expressions to include files:
4:41:05 PM:    - next
4:41:05 PM:    - @ampproject/toolbox-optimizer
4:41:05 PM:
4:41:05 PM:   Because files included with dynamic expressions aren't bundled with your serverless functions by default,
  this may result in an error when invoking a function. To resolve this error, you can mark these Node.js
4:41:05 PM:   modules as external in the [functions] section of your `netlify.toml` configuration file:
4:41:05 PM:
4:41:05 PM:   [functions]
4:41:05 PM:     external_node_modules = ["next", "@ampproject/toolbox-optimizer"]
4:41:05 PM:
4:41:05 PM:   Visit https://ntl.fyi/dynamic-imports for more information.
```

We added this warning at a time when we weren't able to do anything about these imports, so flagging any potential issues was our best option. Now, we're actually capable of handling some of these imports, so this warning becomes misleading.

**- What is the expected behavior?**

We should only include in this warning modules with dynamic imports that we weren't able to solve.

[HIDDEN]

### Additional contract requirements

- For Node functions bundled with esbuild, `nodeModulesWithDynamicImports` must include modules whose dynamic imports could not be resolved or handled during bundling, and exclude modules whose dynamic imports were successfully handled.
