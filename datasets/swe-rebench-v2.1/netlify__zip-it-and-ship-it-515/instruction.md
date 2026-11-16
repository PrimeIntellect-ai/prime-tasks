Error occurs when plugin uses listAll to get list of modules from typescript file
<!--
If you are reporting a new issue, make sure that we do not have any duplicates
already open. You can ensure this by searching the issue list for this
repository. If there is a duplicate, please close your issue and add a comment
to the existing issue instead.

If you suspect your issue is a bug, please edit your issue description to
include the BUG REPORT INFORMATION shown below. If you fail to provide this
information within 7 days, we cannot debug your issue and will close it. We
will, however, reopen it if you later provide the information.

---------------------------------------------------
BUG REPORT INFORMATION
---------------------------------------------------
Use the commands below to provide key information from your environment:
You do NOT have to include this information if this is a FEATURE REQUEST
-->

**- Do you want to request a _feature_ or report a _bug_?**
Bug

**- What is the current behavior?**
Error: Could not list Netlify Functions files

I am using  the `netlify-plugin-inline-functions-env` plugin which [calls `functions.listAll`](https://github.com/bencao/netlify-plugin-inline-functions-env/blob/c3866ce029bb93b35ed3000e554be8c85be8892a/index.js#L36) that's passed in by the netlify builder. The function call produces the above-mentioned error when a `ts` function file is importing another `ts` file.
```
import example from '../utils/example'; // importing from `../utils/example.ts` produces the error
```

[HIDDEN]
Not quite sure why it is defaulting to the legacy bundler, I believe the default bundler is supposed to be esBuild now?

**- If the current behavior is a bug, please provide the steps to reproduce.**
1. Add `netlify-plugin-inline-functions-env` plugin for netlify builds
2.  Write a function in `.ts` e.g. `main.ts`
3. Write another helper module e.g. `../utils/example.ts`
4. Import module within `main.ts` e.g. `import example from '../utils/example.ts'`
5. run `netlify build`

This will trigger an error during the inlining because it uses the `listAll` function injected from within this repo.

**- What is the expected behavior?**
Build successfully completes.

**- Please mention your node.js, and operating system version.**
node v12.16.1
MacOS v11.3.1

### Additional contract requirements

- When `functions.listAll` is used for a TypeScript function that imports another TypeScript module, listing must complete successfully.
