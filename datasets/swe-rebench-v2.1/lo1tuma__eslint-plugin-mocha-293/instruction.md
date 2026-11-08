no-setup-in-describe function expression false positives
no-setup-in-describe thinks that the bodies of function expressions are executed as part of the describe block:

```javascript
describe('description', function () {
  const x = {};

  const foo = function () {
    // mocha/no-setup-in-describe: Unexpected member expression in describe block. Member
    // expressions may call functions via getters
    x.a = 'foo';
  };

  function bar() {
    x.a = 'bar'; // OK
  }

  const baz = () => {
    x.a = 'baz'; // OK
  };

  it('example', async function () {
    foo();
    bar();
    baz();
  });
});
```

Versions:
* eslint-plugin-mocha 8.0.0
* eslint 7.13.0
* mocha 8.2.1
* node 14.14.0
