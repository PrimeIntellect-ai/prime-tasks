withJson accepts template name
**Is your feature request related to a problem? Please describe.**
Able to use `withTemplate` in spec

**Describe the solution you'd like**
```js
await spec()
 .post('/api/users')
 .withJson('USERS:WORKEMAIL')
 .expectStatus(200)
```

**Describe alternatives you've considered**
NA

**Additional context**
NA
