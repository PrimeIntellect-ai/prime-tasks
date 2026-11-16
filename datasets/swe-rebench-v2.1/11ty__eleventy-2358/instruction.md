Custom template fails to render in v1.0.1
**Describe the bug**
I'm using Eleventy custom templates to handle sass files with template skips via .startsWith('_'); as described by this example here: https://www.11ty.dev/docs/languages/custom/#skipping-a-template-from-inside-of-the-compile-function. However since updating to Eleventy v1.0.1 my test builds have started to fail with the following error:

```
[11ty] 1. Having trouble rendering scss template ./source/assets/styles/_callout.scss (via TemplateContentRenderError)
[11ty] 2. Having trouble compiling template ./source/assets/styles/_callout.scss (via TemplateContentCompileError)
[11ty] 3. Cannot read properties of undefined (reading 'bind') (via TypeError)
[11ty]
[11ty] Original error stack trace: TypeError: Cannot read properties of undefined (reading 'bind')
[11ty]     at *[project path]*/node_modules/.pnpm/@11ty+eleventy@1.0.1/node_modules/@11ty/eleventy/src/Engines/Custom.js:173:35
```

**To Reproduce**
Steps to reproduce the behavior:

1. Follow example from https://www.11ty.dev/docs/languages/custom/ on adding sass support to Eleventy
2. Implement early returning from the `compile()` function with a `.startsWith('_')` conditional as described here: https://www.11ty.dev/docs/languages/custom/#skipping-a-template-from-inside-of-the-compile-function
3. Run build

**Expected behavior**
Given no apparent syntax errors in the compile function code, I expected that Eleventy v1.0.1 would process the scss files and output them to the output directory

**Environment:**

- Ubuntu 21.10 via kernal 5.10.102.1-microsoft-standard-WSL2
- Eleventy Version v1.0.1

**Additional context**
1. What's odd to me is that the error persists even when returning early from the compile function, meaning that something is catching on the eleventy side rather than as an issue with my implementation or with `sass`, it's puzzling to me why the error is being thrown when attempting to compile a file that should be skipped; `_callout.scss` in this case.
2. Reverting to Eleventy v1.0.0 appears to fix this issue so it's definitely a byproduct of updating
3. Creating a reduced test case with just the configuration required and a couple of .scss files doesn't appear to reproduce the issue which means that there's something specific to my project that was working on v1.0.0 and now on v1.0.1 it's not. Happy to help triage the issue if Zach or a contributor has any ideas on what to try next.
