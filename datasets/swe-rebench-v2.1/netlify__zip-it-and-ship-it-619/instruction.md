Allow `.mjs` entrypoints for functions
**- Do you want to request a _feature_ or report a _bug_?**

Feature

**- What is the current behavior?**

While zisi can bundle ESM files with`.mjs` extensions, it does not recognize them as entrypoints.

**- If the current behavior is a bug, please provide the steps to reproduce.**

1. Create a function in `netlify/functions/hello/hello.mjs`
2. Run `zip-it-and-ship-it netlify/functions out_functions`

**- What is the expected behavior?**
The function `hello` is bundled, defaulting to esbuild
