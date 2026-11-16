Add support for the import assertions proposal
For example, this import statement should be passed through in ESM mode and the assert declaration should be removed in CJS mode:
```js
import foo from "foo.json" assert {type: "json"};
...
export {val} from './foo.js' assert {type: "javascript"};
```

Proposal is here: https://github.com/tc39/proposal-import-assertions

Babel implements the parsing for this at https://github.com/babel/babel/pull/12139
Support for transpiling imports with `assert {type: "json"}` to use the old native way of node:fs ?
Consider looking at this code: https://deno.land/x/emoji@0.2.1/emoji.ts?source
It has `assert`, which crashes sucrase:
![image](https://user-images.githubusercontent.com/92968534/189516084-ce28a5a3-5fea-491b-a5ef-fc53f593b602.png)

The 4th line has `assert`.
