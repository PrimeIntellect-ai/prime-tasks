setting options requires one setting all options
Code to reproduce:
```js
const md = require('markdown-it')();
const markdownItAttrs = require('./');

md.use(markdownItAttrs, {
  allowedAttributes: ['id', 'class', /^regex.*$/]
});

let src = 'asdf *asd*{.c} khg';

let res = md.render(src);

console.log(res);  // eslint-disable-line
```

Current result: Throws error
```
/Users/arve/git/markdown-it-attrs/utils.js:227
  return s.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&');
           ^

TypeError: Cannot read property 'replace' of undefined
    at Object.escapeRegExp (/Users/arve/git/markdown-it-attrs/utils.js:227:12)
    at module.exports.options (/Users/arve/git/markdown-it-attrs/patterns.js:11:35)
    at Function.attributes (/Users/arve/git/markdown-it-attrs/index.js:16:20)
    at MarkdownIt.use (/Users/arve/git/markdown-it-attrs/node_modules/markdown-it/lib/index.js:496:10)
    at Object.<anonymous> (/Users/arve/git/markdown-it-attrs/debug.js:5:4)
    at Module._compile (internal/modules/cjs/loader.js:689:30)
    at Object.Module._extensions..js (internal/modules/cjs/loader.js:700:10)
    at Module.load (internal/modules/cjs/loader.js:599:32)
    at tryModuleLoad (internal/modules/cjs/loader.js:538:12)
    at Function.Module._load (internal/modules/cjs/loader.js:530:3)
```

Expected result: Should not throw error.

Reported in https://github.com/kidonng/markdown-it-attrs/pull/1
