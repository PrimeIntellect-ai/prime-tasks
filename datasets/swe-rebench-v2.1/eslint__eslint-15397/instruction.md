Bug: max-lines-per-function changes in eslint 8.4.0
### Environment

Node version: 16.13.1
npm version: 8.1.2
Local ESLint version: 8.4.0
Global ESLint version: none
Operating System: Windows 10 21H1, Alpine Linux 3.14


### What parser are you using?

Default (Espree)

### What did you do?

With the changes to `max-lines-per-function` in v8.4.0 per https://github.com/eslint/eslint/pull/15140, this rule cannot be disabled at the start of the function with `// eslint-disable-next-line max-lines-per-function`, which did work in previous versions and has made this a breaking change. The rule now flags this disable as unused since no problems are reported for `max-lines-per-function` on this line, and flags an error on the first line that exceeds the line length limit.

<details>
<summary>Configuration</summary>

```
module.exports = {
    env: {
        es6: true,
        node: true
    },
    extends: ['eslint:recommended'],
    reportUnusedDisableDirectives: true,
    rules: {
        'max-lines-per-function': ['error', { 'max': 5}]
    }
};
```
</details>

```js
// eslint-disable-next-line max-lines-per-function -- flagged as unused
const foo = () => {
    const x = 1;
    console.log(x);
    console.log(x);
    console.log(x);
    console.log(x); // error is flagged here and subsequent lines
    console.log(x);
    console.log(x);
    console.log(x);
    console.log(x);
};
```


### What did you expect to happen?

`// eslint-disable-next-line max-lines-per-function` should disable the rule for a function exceeding the max lines, and should not be listed as unused

### What actually happened?

`// eslint-disable-next-line max-lines-per-function` before the function is listed as unused.  The only way to disable for the function appears to be wrapping it with `disable`/`enable` comments, as shown below. This limits the options to disable the rule, e.g. you might want to disable for a factory function, but enable the rule for any internally defined functions, which isn't an option with this disable.

```js
/* eslint-disable max-lines-per-function */
const foo = () => {
    const x = 1;
    console.log(x);
    console.log(x);
    console.log(x);
    console.log(x);
    console.log(x);
    console.log(x);
    console.log(x);
    console.log(x);
};
/* eslint-enable max-lines-per-function */
```

### Participation

- [ ] I am willing to submit a pull request for this issue.

### Additional comments

_No response_

### Additional contract requirements

- For an `exceed` diagnostic, include `lineCount` (the total counted lines in the function) in the diagnostic data, alongside `name` and `maxLines`.
