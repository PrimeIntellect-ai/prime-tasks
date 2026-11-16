Add option to disable TS import/export elision
Follow-up from #783

## Background

TypeScript 5.0 released a new option `--verbatimModuleSyntax`, and this issue tracks the implementation of some kind of equivalent option. The new TS option is described here: https://devblogs.microsoft.com/typescript/announcing-typescript-5-0/#verbatimmodulesyntax .

The option actually has two behaviors:
1. Disable all automatic import/export elision (removal of type-only or unused imports and exports), and instead require explicit `type` syntax.
2. Disallow all ESM -> CJS conversion.

I'm glad to see behavior 1 as a replacement for the now-deprecated `--importsNotUsedAsValues` and `--preserveValueImports`, since it has much simpler behavior and fully avoids the need for Sucrase to track variables and scopes.

I have mixed feelings about behavior 2, and I'm not sure it makes sense for Sucrase to bundle the two behaviors together the way TS does. The TS behavior seems to be entirely error-checking, not affecting emit, so one interpretation is that Sucrase should simply ignore behavior 2 since Sucrase leaves error checking to other tools. Another interpretation is that Sucrase should disallow setting this flag and the `imports` transform at the same time, or have the flag automatically disable the `imports` transform, but both of those seem a bit strange and arbitrary as opposed to the two options being independently configurable (which should be easy to implement). The codebase I work with at work is an example of a situation where ESM -> CJS transformation is still needed and it would be nice to avoid import/export elision for better understandability.

That said, I am happy to see a potential future path where `.cts` files no longer attempt to simulate ESM in CJS, which would mean that Sucrase would be able to eventually fully sunset the `imports` transform even if CJS has some occasional legacy uses.

## Details

The plan for this task is to create a new flag that disables all import/export elision from the `typescript` transform. This was actually previously proposed with a PR in https://github.com/alangpierce/sucrase/pull/615 , so that will be a good starting point. All normal ESM syntax will need a `type` keyword to remove the whole statement or parts of it. When used with the `imports` transform, the `type` syntax will determine whether to remove the `require` call.

Since the behavior is a little different from TS `verbatimModuleSyntax` (since there's no behavior 2 mentioned above), it's probably best to give it a different name. The decision on name can come later, but some options that come to mind:
* `keepUnusedImports` (used in the linked PR)
* `preserveTSImports`
* `disableImportExportElision`

### Additional contract requirements

The caller-configurable option is named `keepUnusedImports`. When enabled for the TypeScript transform, it disables automatic import/export elision: unused and type-only syntax is retained unless explicit `type` syntax marks the statement or specifier for removal. With the imports transform enabled, explicit `type` syntax also determines whether the corresponding `require` call is removed. This option does not prohibit ESM-to-CommonJS conversion.
