object-curly-newline counts default export in minProperties
**Tell us about your environment**

Ubuntu 17.10

* **ESLint Version:** 4.19.0
* **Node Version:** 9.6.1
* **npm Version:** 5.7.1

(Also validated on OSX, Node 7.10.0, npm 4.2.0)

**What parser (default, Babel-ESLint, etc.) are you using?**

Default, I believe(?), with sourceType: module. Full configuration:

<details>
<summary>Configuration</summary>

`.eslintrc`
```json
{
	"root": true,
	"env": { "es6": true },
	"extends": [
		"eslint:recommended"
	],
	"parserOptions": {
		"sourceType": "module"
	},
	"rules": {
		"object-curly-newline": [ "error", {
			"minProperties": 2,
			"consistent": true
		} ]
	}
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

[This gist](https://gist.github.com/kadamwhite/f0098c63df2f9edf5d79b8b8b8b446f5) contains the `package.json`, `.eslintrc` and `test.js` as described here; downloading that gist, running `npm install` and then `npm test` replicates the issue on every environment I can access.

<!-- Paste the source code below: -->
`test.js`
```js
import DefaultExport, { NamedExport } from 'some-module';
import { NamedExportWithoutDefaultImport } from 'some-other-module';

export default {
  DefaultExport,
  NamedExport,
  NamedExportWithoutDefaultImport,
};
```
`package.json`
```json
{
  "name": "test-object-curly-newline",
  "scripts": {
    "test": "eslint ./test.js"
  },
  "devDependencies": {
    "eslint": "^4.19.0"
  }
}
```
<!-- Paste the command you used to run ESLint: -->
```bash
npm test # runs `eslint ./test.js`
```

**What did you expect to happen?**

I expected no `object-curly-newline` issue to be reported for either of these imports, as they both have only a single named export within curly brackets:
```js
import DefaultExport, { NamedExport } from 'some-module';
import { NamedExportWithoutDefaultImport } from 'some-other-module';
```
however the default export on the first line is being counted as an object property, meaning that the rule matches the `minProperties` and I get errors for each curly bracket on Line 1, but not Line 2

**What actually happened? Please include the actual, raw output from ESLint.**

```
$ npm test

> test-object-curly-newline@ test /hm/gh/coding-standards/packages/eslint-config-humanmade/test
> eslint ./test.js


/hm/gh/coding-standards/packages/eslint-config-humanmade/test/test.js
  1:23  error  Expected a line break after this opening brace   object-curly-newline
  1:37  error  Expected a line break before this closing brace  object-curly-newline

✖ 2 problems (2 errors, 0 warnings)
  2 errors, 0 warnings potentially fixable with the `--fix` option.

npm ERR! Test failed.  See above for more details.
```
