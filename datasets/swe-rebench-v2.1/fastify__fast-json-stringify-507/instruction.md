possible performance impact when updating from v4.2.0 to v5.0.0
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the issue has not already been raised


### Issue

Hi!

Today I was doing some dependency updates for my fastify apps, when I noticed a bigger InitDuration for my AWS Lambdas.
To have an idea my [await app.ready()](https://github.com/fastify/aws-lambda-fastify#lower-cold-start-latency) call went from approx. 400ms to approx. 1600ms _(on AWS Lambda this went up to 18000ms and also caused some timeouts)_ by updating from fastify [v4.1.0 to v4.2.0](https://github.com/fastify/fastify/compare/v4.1.0...v4.2.0#diff-7ae45ad102eab3b6d7e7896acd08c427a9b25b346470d7bc6507b6481575d519).

After some testing I'm assuming that probably fast-json-stringify is causing this because of [this commit](https://github.com/fastify/fast-json-stringify/commit/a5e307987e3220dc93692cb7b0eca1f88c46da04).

I'm not so familiar with the internals, but this simple test, helped me to compare a bit more.

For example by wrapping the `refFinder(schema.$ref, location)` call here: https://github.com/fastify/fast-json-stringify/blob/v4.2.0/index.js#L108 in v4.2.0
i.e. like this:
```js
const d = Date.now()
location = refFinder(schema.$ref, location)
console.log('refFinder', Date.now() - d)
```
I basically get always 0 ms for the time measurements for all invocations, but compared to the newer `ajvInstance.getSchema(schemaRef)` call here: https://github.com/fastify/fast-json-stringify/blob/v5.0.0/index.js#L64 in v5.0.0
i.e. like this:
```js
const d = Date.now()
ajvSchema = ajvInstance.getSchema(schemaRef)
console.log('ajvInstance.getSchema', Date.now() - d)
```
I'm now getting 2-20ms for the time measurements for the different invocations.

<img width="171" alt="image" src="https://user-images.githubusercontent.com/1086194/185762649-a8ae4730-8f13-4a97-a87b-ac20655ec595.png">
<img width="196" alt="image" src="https://user-images.githubusercontent.com/1086194/185762656-b6d218a0-8396-4e59-b0be-98d62410e080.png">


Like said, I'm not familiar with these internals, but I assume [ajv.getSchema](https://ajv.js.org/api.html#ajv-getschema-key-string-undefined-data-any-boolean-promise-any) is getting the [fastify.ready()](https://www.fastify.io/docs/latest/Reference/Server/#ready) call much slower.

I'm sorry for my unprofessional reproduction steps, but I hope this information may help to understand the issue.

### Additional contract requirements

When compiling schemas with many `$ref` references, reference resolution should not cause a substantial slowdown as the number of registered schemas and references grows. Compilation should scale approximately with the size of the input schema rather than repeatedly searching the full registered-schema set for each reference. Existing supported schema-reference forms and their serialization behavior must be preserved.
