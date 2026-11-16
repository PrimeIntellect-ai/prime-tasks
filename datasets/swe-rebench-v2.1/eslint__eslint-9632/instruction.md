`System` not detected as an undefined variable
**Tell us about your environment**

* **ESLint Version:** 4.11.0
* **Node Version:** 8.6.0

**What parser (default, Babel-ESLint, etc.) are you using?**
default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```yaml
root: true
extends: eslint:recommended
parserOptions:
  ecmaVersion: 2017
  ecmaFeatures:
    impliedStrict: true
  sourceType: module
env:
  es6: true
  node: true
  mocha: true
  jasmine: true
rules:
  linebreak-style:
    - error
    - unix
  max-len:
    - warn
    - code: 80
      tabWidth: 2
      ignoreComments: true
      ignoreUrls: true
      ignoreTemplateLiterals: true
      ignoreRegExpLiterals: true
      ignorePattern: require\('
  indent:
    - error
    - 2
    - SwitchCase: 1
      VariableDeclarator:
        let: 2
        const: 3
      MemberExpression: off
  semi:
    - error
    - always
  consistent-this:
    - error
    - self
    - $ctrl
  quotes:
    - error
    - single
    - allowTemplateLiterals: true
  quote-props:
    - error
    - as-needed
  curly:
    - error
    - all
  comma-dangle:
    - error
    - always-multiline
  new-cap:
    - error
    - newIsCap: true
      capIsNew: true
      properties: false
  camelcase:
    - error
    - properties: never
  array-bracket-spacing:
    - error
    - never
  arrow-spacing:
    - error
    - before: true
      after: true
  block-spacing:
    - error
    - always
  comma-spacing:
    - error
    - before: false
      after: true
  computed-property-spacing:
    - error
    - never
  generator-star-spacing:
    - error
    - before: true
      after: false
  key-spacing:
    - error
    - beforeColon: false
      afterColon: true
      mode: minimum
  keyword-spacing:
    - error
    - before: true
  semi-spacing:
    - error
    - before: false
      after: true
  space-in-parens:
    - error
    - never
  space-unary-ops:
    - error
    - words: true
      nonwords: false
  space-before-function-paren:
    - error
    - anonymous: never
      named: never
      asyncArrow: always
  space-before-blocks:
    - error
    - always
  yoda:
    - error
    - never
  wrap-iife:
    - error
    - outside
  eqeqeq:
    - error
    - always
  newline-per-chained-call:
    - error
    - ignoreChainWithDepth: 3
  one-var-declaration-per-line:
    - error
    - initializations
  brace-style:
    - error
    - stroustrup
  no-implicit-coercion:
    - error
    - boolean: false
  no-global-assign:
    - error
    - exceptions:
        - Promise
  eol-last: error
  dot-notation: error
  space-infix-ops: error
  no-with: error
  no-unreachable: error
  no-redeclare: error
  no-unexpected-multiline: error
  no-multi-spaces: error
  no-multi-str: error
  no-trailing-spaces: error
  no-mixed-spaces-and-tabs: error
  no-spaced-func: error
  no-whitespace-before-property: error
  no-unsafe-negation: error
  no-lonely-if: error
  no-var: error
  no-console: off
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
console.log(System);
console.log(Blah);
```
(in test.js)

<!-- Paste the command you used to run ESLint: -->
```bash
eslint test.js
```

**What did you expect to happen?**
I expect to see two errors;

1) 'System' is not defined
2) 'Blah' is not defined

**What actually happened? Please include the actual, raw output from ESLint.**
Only one error is shown:

```
  3:13  error  'Blah' is not defined  no-undef

✖ 1 problem (1 error, 0 warnings)
```

I've tried this across many files -- for some reason it doesn't flag `System` as an undefined variable, ever. I looked to see if I had it defined as a global, or if it was defined as a global in the [recommended preset](https://github.com/eslint/eslint/blob/master/conf/eslint-recommended.js), but it wasn't. It's also not a [global in Node](https://nodejs.org/api/globals.html), and the output of the console log is `undefined`.
