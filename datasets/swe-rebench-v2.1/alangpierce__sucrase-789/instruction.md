Dynamic import not act as expected as typescript transpiled
Here is the example:

https://sucrase.io/#compareWithBabel=false&compareWithTypeScript=true&code=import%20b%20from%20'a'%3B%0A%0Aasync%20function%20a%20()%20%7B%0A%20%20console.log(b)%3B%0A%20%20const%20c%20%3D%20await%20import('a')%3B%0A%20%20console.log(c)%3B%0A%20%20console.log(c.default)%3B%0A%7D

While static import is transpiled to use `_interopRequireDefault`, but [HIDDEN], so in runtime `c.default` is not defined.

### Additional contract requirements

- For a dynamic `import()` of a plain CommonJS module (a module without an `__esModule` marker), the resolved module namespace must expose the module's exported value under its `default` property, consistent with Node's ESM-to-CJS dynamic import and with Babel/TypeScript interop.
