Jest doesn't show the name of the field causing the error
I wrote my first test using Frisby and I got a strange behaviour.

This is a portion of my test file:

```
    it('check function', function (done) {
      frisby.get(BASE_URL + 'check')
        .expect('status', 200)
        .done(done);
    });

    it('user login', function (done) {
      frisby.post(BASE_URL + 'login', user)
        .expect('status', 200)
        .expect('jsonTypes', 'id', Joi.number().required())
        .expect('jsonTypes','email', Joi.string().email().required())
        .expect('json','emailConfirmed', 1)
        .expect('jsonTypes','name', Joi.string().required())
        .expect('jsonTypes','surname', Joi.string().required())
        .expect('jsonTypes','avatar', Joi.string())
        .expect('jsonTypes','city', Joi.string().required())
        .expect('jsonTypes','token', Joi.string().required())
        .expect('json','role', 'user')
        .done(done);
    });

```
and it works fine!

If I change this row
```
    .expect('jsonTypes','name', Joi.string().required())
```

with the following one
```
    .expect('jsonTypes','name', Joi.number().required())
```

I get this output


```
    ● user login

        ValidationError: "value" must be a number

          at Object.<anonymous>.exports.process (node_modules/joi/lib/errors.js:152:19)
          at Object.<anonymous>.internals.Number.Object.<anonymous>.internals.Any._validateWithOptions (node_modules/joi/lib/any.js:633:27)
          at Object.<anonymous>.module.exports.internals.Any.root.validate (node_modules/joi/lib/index.js:104:23)
          at jsonTypesAssertion (node_modules/frisby/src/frisby/expects.js:104:24)
          at Object.withPath (node_modules/frisby/src/frisby/utils.js:67:12)
          at FrisbySpec.jsonTypes (node_modules/frisby/src/frisby/expects.js:103:11)
          at FrisbySpec._addExpect.response (node_modules/frisby/src/frisby/spec.js:368:23)
          at FrisbySpec._runExpects (node_modules/frisby/src/frisby/spec.js:260:24)
          at _fetch.fetch.then.then.responseBody (node_modules/frisby/src/frisby/spec.js:139:14)
          at process._tickCallback (internal/process/next_tick.js:109:7)
```

I should expect to receive
```
    "name" must be a number
```
in order to immediately identify the error in my API.

Moreover, if I change my API removing the field "name", I get this output

```
      ● user login

        ValidationError: "value" is required
```
Same problem: the field name is not printed.

It seems that Jest shows the Joi output, and Joi doesn't know the field name. But Jest does, so it should show the proper name of the field causing the error.

Am I missing something?

### Additional contract requirements

- The `jsonTypesStrict` expectation also accepts an optional dot-notation path as its second argument, followed by a Joi schema as its third argument. When a path is supplied and the value at that path fails validation, the error message uses the supplied path as the label (for example `"user.name" must be a number`) instead of the default `"value"` label.
