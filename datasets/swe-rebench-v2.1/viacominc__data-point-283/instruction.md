should be able to fully override request.param.inspect
<!--
Thanks for your interest in the project. We appreciate bugs filed and PRs submitted!
Please make sure that you are familiar with and follow the Code of Conduct for
this project (found in the CODE_OF_CONDUCT.md file).

Please fill/un-comment out this template with all the relevant information so we can
understand what's going on and fix the issue.
-->

**Problem description**:

Wehn attempting to override request.params.inspect with a function the inspect works but it outputs other information aside from the custom function.

**Suggested solution**:

When inspect is overridden it should pass the necessary information to print:
- entityId
- options
- acc

and the output should be 100% delegated to this method

<!--
REPORTING BUG:

If you are reporting a bug, please provide the full error message/screenshots/anything.
-->

**What happened**:

Code below was expected to only print out 'hello':

```js
'request:foo': {
  url: 'http://some.url.com',
  params: {
    inspect: (acc) => {
       console.log('hello')
    }
  }
}
```

But it printed:

```bash
inspect: request:foo
options: {
  "method": "GET",
  "json": true,
  "url": "http://some.url.com"
}
value: {}

custom:
hello
```

**Reproduction**:

```js
const dp = require('data-point').create({
  entities: {
    'request:getVehicle': {
      url: 'https://swapi.co/api/vehicles/14/',
      params: {
        inspect: (acc) => {
          console.log('hello')
        }
      }
    }
  }
})

dp.resolve('request:getVehicle', {})
```
<!--If you have a link or example that reproduces your issue please include it. A reproduction with as little code as possible is better.-->

**Environment**:

- `data-point` version: 3.1.0
- `node` version: 8
- `npm` version: N/A
