error: no-assigning-return-values: Do not assign return value of Cy command
I just added the `eslint-plugin-cypress` to the Cypress documentation. So now our linter is running against our examples in our documentation.

There are some examples we have in the docs that are erroring in the eslint-plugin, which I have to think should not be erroring since they are recommended uses of cypress. Can we make this rule exclude assignments of `cy.spy` or `cy.stub`?

1. `error  cypress/no-assigning-return-values: Do not assign the return value of a Cypress command` There are other examples in stub as well like `const stub = cy.stub()`
  https://docs.cypress.io/api/commands/spy.html#Aliases
  ```js
  const obj = {
    foo () {}
  }
  const spy = cy.spy(obj, 'foo').as('anyArgs')
  const withFoo = spy.withArgs('foo').as('withFoo')

  obj.foo()
  expect(spy).to.be.called
  expect(withFoo).to.be.called // purposefully failing assertion
  ```
