Consider allowing claims object to be formatted.
<!--
Before you submit an issue we recommend you visit [Fastify Help](https://github.com/fastify/help) and ask any questions you have or mention any problems you've had getting started with Fastify.

**Please read this entire template before posting any issue. If you ignore these instructions
and post an issue here that does not follow the instructions, your issue might be closed,
locked, and assigned the `missing discussion` label.**
-->

## 🚀 Feature Proposal

Currently, the claims object obtained by decoding the token is added as `request.user` directly.  An option to format the claims object before could be useful.

## Motivation

The most useful representation of the data in the token is not necessarily the way it was encoded.  Claims may be given names that are abbreviated ("dept_name"), misspelled ("depatment_name"), or confusing ("belongs_to").  Or, maybe it'd just be preferable to have `request.user.departmentName` over `request.user.department_name`.  While this can be handled by following up with overwriting `request.user` with a formatted version
```js
const fastify = require('fastify')();
fastify.register(require('fastify-jwt'), {
  secret: 'supersecret'
});

fastify.addHook('onRequest', async (request, reply) => {
  try {
    await request.jwtVerify();
    request.user = {
      departmentName: request.user.department_name,
      name: request.user.name
    };
  } catch (err) {
    reply.send(err);
  }
});
```

it isn't an elegant solution.

## Example

Ideally, it'd just be an option.

```js
const fastify = require('fastify')();
fastify.register(require('fastify-jwt'), {
  // Takes the claims object and returns a formatted version.
  formatUser: user => ({
    departmentName: user.department_name
    name: user.name
  }),
  secret: 'supersecret'
});

fastify.addHook('onRequest', async (request, reply) => {
  try {
    await request.jwtVerify();
  } catch (err) {
    reply.send(err);
  }
});

fastify.get("/", async (request, reply) => {
  // `request.user` is the object returned by `formatUser`.
  return `Hello, ${request.user.name} from ${request.user.departmentName}.`;
});
```

### Additional contract requirements

- `formatUser` is a synchronous callback provided in the plugin registration options. It receives the decoded JWT claims object and returns the value to expose as the user.
- When `formatUser` is supplied, `request.jwtVerify()` resolves with the value returned by `formatUser`, and `request.user` is set to that same value.
- When `formatUser` is not supplied, `request.jwtVerify()` resolves with the decoded claims object and `request.user` is set to that object.
