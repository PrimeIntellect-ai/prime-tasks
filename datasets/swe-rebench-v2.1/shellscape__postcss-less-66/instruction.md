Cannot read property '2' of undefined
While being run through `stylelint` (itself being run in the Atom package `linter-stylelint`) the following stack trace was hit while attempting to parse `.border`:

```
TypeError: Cannot read property '2' of undefined
    at LessParser.rule (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss-less\dist\less-parser.js:64:38)
    at LessParser.createRule (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss-less\dist\less-parser.js:110:18)
    at LessParser.ruleWithoutBody (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss-less\dist\less-parser.js:141:18)
    at LessParser.processEndOfRule (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss-less\dist\less-parser.js:173:22)
    at LessParser.word (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss-less\dist\less-parser.js:272:44)
    at LessParser.loop (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss-less\dist\less-parser.js:300:30)
    at lessParse (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss-less\dist\less-parse.js:23:12)
    at new LazyResult (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss\lib\lazy-result.js:70:24)
    at Processor.process (C:\Users\Landon Abney\.atom\packages\linter-stylelint\node_modules\postcss\lib\processor.js:117:12)
    at file:///C:/Users/Landon Abney/Documents/GitHub-release/linter-stylelint/node_modules/stylelint/lib/getPostcssResult.js:81:29
```

You can reproduce this by:

* Install Atom, `linter-stylelint` and open a new `.less` file.
* Start typing out a class name, at some point during typing it you will get a popup of the `Cannot read property '2' of undefined` error
* You can get a stack trace by placing a breakpoint [here](https://github.com/AtomLinter/linter-stylelint/blob/v3.8.1/lib/index.js#L202)

I'm sure there are more direct ways of triggering this 😛.

_Note: Originally filed as https://github.com/AtomLinter/linter-stylelint/issues/181_

### Additional contract requirements

- When parsing the incomplete LESS input `.foo`, reject with a `CssSyntaxError`.
