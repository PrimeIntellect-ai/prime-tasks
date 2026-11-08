Add .d.ts files with types declaration
* [x] prepare `*.d.ts` files - https://www.typescriptlang.org/docs/handbook/declaration-files/templates/module-d-ts.html
* [ ] ~use [`check-dts` for testing `*.d.ts` files](https://github.com/ai/check-dts)~

<img width="796" alt="Screenshot 2021-08-04 at 14 59 00" src="https://user-images.githubusercontent.com/1929317/128194122-74f779ca-a60b-468f-93b8-fabdf8457ef5.png">

### Additional contract requirements

- The package must ship TypeScript declaration files (`.d.ts`). `package.json` must expose the declaration entry point via a `types` (or `typings`) field pointing to an existing `.d.ts` file; if no such field is present, the declaration file must sit next to the `main` entry (e.g. `lib/index.d.ts` for `main: "./lib/index.js"`).
- The declaration file must declare the public `analyze` function and its `Promise` result.


- In the declaration file, declare `analyze` with function-declaration syntax (`analyze(...)`) and a `Promise` return type.
