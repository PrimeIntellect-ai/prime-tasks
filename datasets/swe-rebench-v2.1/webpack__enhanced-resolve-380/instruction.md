`extensionAlias` is not applied to module exports
Let’s say we have a TypeScript mono repo with one package that depends on another. The actual TypeScript configuration is left out, because it’s not needed for this example.

`webpack.config.js`:

```js
/** @type {import('webpack').Configuration} */
export default {
  entry: './packages/foo/index.ts',
  mode: 'development',
  resolve: {
    extensions: ['.js', '.ts'],
    extensionAlias: {
      '.js': ['.js', '.ts']
    }
  }
}
```

`package.json`:

```json
{
  "type": "module",
  "workspaces": [
    "packages/*"
  ],
  "dependencies": {
    "webpack": "^5.0.0",
    "webpack-cli": "^4.0.0"
  }
}
```

`foo/packages/package.json`:

```json
{
  "name": "foo",
  "type": "module",
  "exports": "./index.js"
}
```

`foo/packages/index.ts`:

```ts
import { bar } from 'bar'

console.log(bar)
```

`bar/packages/package.json`:

```json
{
  "name": "bar",
  "type": "module",
  "exports": "./index.js"
}
```

`bar/packages/index.ts`:

```ts
export const bar = 'bar'
```

Now if we build using Webpack, it throws the following error:

```
~/Projects/bug$ webpack
asset main.js 2.34 KiB [emitted] (name: main)
runtime modules 274 bytes 1 module
./packages/foo/index.ts 44 bytes [built] [code generated]

ERROR in ./packages/foo/index.ts 1:0-25
Module not found: Error: Can't resolve 'bar' in '/home/remco/Projects/bug/packages/foo'
resolve 'bar' in '/home/remco/Projects/bug/packages/foo'
  Parsed request is a module
  using description file: /home/remco/Projects/bug/packages/foo/package.json (relative path: .)
    Field 'browser' doesn't contain a valid alias configuration
    resolve as module
      /home/remco/Projects/bug/packages/foo/node_modules doesn't exist or is not a directory
      /home/remco/Projects/bug/packages/node_modules doesn't exist or is not a directory
      looking for modules in /home/remco/Projects/bug/node_modules
        single file module
          using description file: /home/remco/Projects/bug/package.json (relative path: ./node_modules/bar)
            no extension
              Field 'browser' doesn't contain a valid alias configuration
              /home/remco/Projects/bug/node_modules/bar is not a file
            .js
              Field 'browser' doesn't contain a valid alias configuration
              /home/remco/Projects/bug/node_modules/bar.js doesn't exist
            .ts
              Field 'browser' doesn't contain a valid alias configuration
              /home/remco/Projects/bug/node_modules/bar.ts doesn't exist
        existing directory /home/remco/Projects/bug/node_modules/bar
          using description file: /home/remco/Projects/bug/node_modules/bar/package.json (relative path: .)
            using exports field: ./index.js
              using description file: /home/remco/Projects/bug/node_modules/bar/package.json (relative path: ./index.js)
                no extension
                  Field 'browser' doesn't contain a valid alias configuration
                  /home/remco/Projects/bug/node_modules/bar/index.js doesn't exist
                .js
                  Field 'browser' doesn't contain a valid alias configuration
                  /home/remco/Projects/bug/node_modules/bar/index.js.js doesn't exist
                .ts
                  Field 'browser' doesn't contain a valid alias configuration
                  /home/remco/Projects/bug/node_modules/bar/index.js.ts doesn't exist
                as directory
                  /home/remco/Projects/bug/node_modules/bar/index.js doesn't exist
      /home/remco/Projects/node_modules doesn't exist or is not a directory
      /home/remco/node_modules doesn't exist or is not a directory
      /home/node_modules doesn't exist or is not a directory
      /node_modules doesn't exist or is not a directory
```

This shows that `extensionAlias` isn’t applied when resolving `import 'bar'` from the `foo` project. This can be worked around by removing the `exports` field from `package.json`, but that will cause Node.js to show deprecation warnings if the package would be published and consumed.

### Additional contract requirements

- `ResolverFactory.createResolver(options)` is a public API of the package that creates a resolver instance exposing a `resolve` method.
- `resolver.resolve(context, path, request, resolveContext, callback)` resolves `request` starting from the directory `path`. `context` and `resolveContext` may be empty objects. On success `callback` is called with a falsy error and the resolved absolute filename as the result; on failure `callback` is called with an `Error`.
- The resolver options accept `extensions` (a list of default extensions), `extensionAlias` (an object whose keys are source extensions such as `".js"` and whose values are either a single alias string such as `".ts"` or an array of alias strings such as `[".ts", ".js"]`), `fileSystem`, `fullySpecified` and `conditionNames`.
- When a request ends with a source extension listed in `extensionAlias`, resolution is attempted for each of the alternative extensions given by the mapping, in order, until one resolves, including when the request is resolved through a package `exports` field. If none of the alternatives can be resolved, resolution fails with an `Error`.
