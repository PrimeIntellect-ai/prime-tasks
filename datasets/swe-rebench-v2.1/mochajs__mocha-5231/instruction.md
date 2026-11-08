🚀 Feature: Allow to set timeout on before/after/beforeEach/afterEach in declaration
### Feature Request Checklist

- [X] I have read and agree to Mocha's [Code of Conduct](https://github.com/mochajs/mocha/blob/main/.github/CODE_OF_CONDUCT.md) and [Contributing Guidelines](https://github.com/mochajs/mocha/blob/main/.github/CONTRIBUTING.md)
- [X] I have searched for [related issues](https://github.com/mochajs/mocha/issues?q=is%3Aissue) and [issues with the `faq` label](https://github.com/mochajs/mocha/issues?utf8=%E2%9C%93&q=is%3Aissue%20label%3Afaq%20), but none matched my issue.
- [ ] I want to provide a PR to resolve this

### Overview

`it` returns a `TestFunction` that has a `timeout` method. This is useful for setting timeouts in slow tests, without needing to define the test code inside a `function() {}` block.
An analogous feature would be useful for the `before/beforeEach/after/afterEach` hooks. The current workaround would be:

```javascript
before(function() {
  this.timeout(3000);
});
```

### Suggested Solution

`before/beforeEach/after/afterEach` could return a `HookFunction`, analogous to `TestFunction`, which has a `timeout` method. The code above could be rewritten:

```javascript
before(() => {}).timeout(3000);
```

### Alternatives

None

### Additional Info

_No response_
