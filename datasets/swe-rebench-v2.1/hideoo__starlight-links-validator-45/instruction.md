More informative error for a specific typo
### Is your feature request related to a problem?

Hi, thanks for a great product! It saves a massive amount of time!

I made a typo and entered a link like the following: `[text](/https://astro.build/)`. The error log provided by the links validator didn't mention the page on which the problem was found. As a result, it was far more challenging to hunt down the bug.

Details: Whenever I prepend a / to the href of a link within a markdown or MDX file within Starlight, it breaks the build. The information given by the links validator includes only the phrase, "The URL must be of scheme file" and a stack trace. However, it includes no other information. Here's an example:
```
 validating links
The URL must be of scheme file
  Stack trace:
    at new NodeError (node:internal/errors:406:5)
    at isValidAsset (C:/c/mono/node_modules/.pnpm/starlight-links-validator@0.7.1_@astrojs+starlight@0.24.2_astro@4.10.2_@types+node@20.14.2_ty_eyzihxfa7kaqghr2icuuqz2pdm/node_modules/starlight-links-validator/libs/validation.ts:154:42)
    at Module.validateLinks (C:/c/mono/node_modules/.pnpm/starlight-links-validator@0.7.1_@astrojs+starlight@0.24.2_astro@4.10.2_@types+node@20.14.2_ty_eyzihxfa7kaqghr2icuuqz2pdm/node_modules/starlight-links-validator/libs/validation.ts:55:9)
    at runHookBuildDone (file:///C:/c/mono/node_modules/.pnpm/astro@4.10.2_@types+node@20.14.2_typescript@5.4.5/node_modules/astro/dist/integrations/hooks.js:409:58)
    at async AstroBuilder.build (file:///C:/c/mono/node_modules/.pnpm/astro@4.10.2_@types+node@20.14.2_typescript@5.4.5/node_modules/astro/dist/core/build/index.js:143:5)
 ELIFECYCLE  Command failed with exit code 1.
```

### Describe the solution you'd like

I'd like an error message that includes the file where the error was found. A line number or the text of the link would be nice if possible.

### Describe alternatives you've considered

I ended up solving it through a recursive process of deleting half the folders in the content directory to find the folder that the error was in, then following a similar process within the folder. Once I saw the actual link I immediately recognized it. If it happens again, I'd probably lean more heavily on git history.

### Additional Context

_No response_
