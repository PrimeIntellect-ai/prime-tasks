pretest fails on fresh clone of repo
When cloning this repo, running `npm install` and then `npm test`, the pretest script fails with 7 errors.

```
❯ npm test

> eslint-plugin-mocha@4.11.0 pretest /Users/macklinu/dev/node/eslint-plugin-mocha
> eslint .


/Users/macklinu/dev/node/eslint-plugin-mocha/lib/rules/no-mocha-arrows.js
  81:25  error  Method 'CallExpression' has a complexity of 6  complexity

/Users/macklinu/dev/node/eslint-plugin-mocha/lib/rules/no-nested-tests.js
  21:25  error  Method 'CallExpression' has a complexity of 5  complexity

/Users/macklinu/dev/node/eslint-plugin-mocha/lib/rules/no-return-and-callback.js
  48:1  error  Function 'isAllowedReturnStatement' has a complexity of 7  complexity

/Users/macklinu/dev/node/eslint-plugin-mocha/lib/rules/no-sibling-hooks.js
  25:25  error  Method 'CallExpression' has a complexity of 5  complexity

/Users/macklinu/dev/node/eslint-plugin-mocha/lib/rules/no-skipped-tests.js
  69:25  error  Method 'CallExpression' has a complexity of 5  complexity

/Users/macklinu/dev/node/eslint-plugin-mocha/lib/rules/valid-suite-description.js
  15:25  error  Method 'CallExpression' has a complexity of 8  complexity

/Users/macklinu/dev/node/eslint-plugin-mocha/lib/rules/valid-test-description.js
  15:25  error  Method 'CallExpression' has a complexity of 8  complexity

✖ 7 problems (7 errors, 0 warnings)

npm ERR! Test failed.  See above for more details.
```

Are these errors that should be fixed, or is this an ESLint rule that should be modified? I'd like to contribute a PR (both for this and other features), but not being able to run the `npm test` script locally is a blocker. Suggestions for next steps would be helpful - would be glad to open a PR. Thanks!

```
eslint-plugin-mocha git/master
❯ node --version
v8.9.4

eslint-plugin-mocha git/master
❯ npm --version
5.6.0
```
