`tsgo` typechecking error in tsx code that passes when using `tsc`
I'm trying out tsgo on my large work codebase and found it errors on a pattern we use very often that does pass `tsc`:

```ts
import type { ComponentType, JSX } from "react"

export type Page<P = NonNullable<unknown>> = ComponentType<P> & {
    getLayout?: (component: JSX.Element) => JSX.Element
}

export const FooPage: Page = () => {
    return (
        <div>
            <p>Foo</p>
        </div>
    )
}

// `tsgo` errors here: "'getLayout' implicitly has type 'any' because it does not have a type annotation
//                                  and is referenced directly or indirectly in its own initializer."
FooPage.getLayout = () => {
    return <></>
}
```

(_And on importing vite's `defineConfig`, but I see someone else beat me to that in #904._)

I was able to reproduce my error in a much more barebones project: https://github.com/justinsmid/tsgo-test
I'm sure the `tsconfig.json` could be simplified, and I'm not sure if it's related to any setting in there, but I wanted to keep the config as close to that of my work repo as I could.

Running `pnpm typecheck` (which uses `tsc`) passes, but `pnpm typecheck-go` does not:

```
> tsgo --noEmit

src/components/Foo.tsx:15:1 - error TS7022: 'getLayout' implicitly has type 'any' because it does not have a type annotation and is referenced directly or indirectly in its own initializer.

15 FooPage.getLayout = () => {
   ~~~~~~~~~~~~~~~~~~~~~~~~~~~
16     return <></>
   ~~~~~~~~~~~~~~~~
17 }
   ~
vite.config.ts:1:10 - error TS2305: Module '"[REDACTED]/tsgo-test/node_modules/.pnpm/vite@6.3.5/node_modules/vite/index"' has no exported member 'defineConfig'.

1 import { defineConfig } from 'vite';
           ~~~~~~~~~~~~

Found 2 errors in 2 files.

Errors  Files
     1  src/components/Foo.tsx:15
     1  vite.config.ts:1

 ELIFECYCLE  Command failed with exit code 2.
```
