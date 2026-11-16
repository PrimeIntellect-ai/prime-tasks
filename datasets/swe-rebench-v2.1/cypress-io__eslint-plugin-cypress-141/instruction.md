cy.focused().type("text") shows cypress/unsafe-to-chain-command error
After an update to 2.14.0, the  cypress/unsafe-to-chain-command rule is triggered by code as
`cy.focused().type("text")`.
This should be no problem however, as the cypress docu states `cy.focused() is a query, and it is safe to chain further commands` (https://docs.cypress.io/api/commands/focused)

### Additional contract requirements

- For the built-in unsafe action names, the rule must only report a chained command when the command method name is exactly that action name. A method name that merely contains a built-in action name as a substring is not an action and must not be reported.
- In particular, `cy.focused().type("text")` must not be reported (`focused` is not the action `focus`), and `cy.submitBtn().click()` must not be reported (`submitBtn` is not the action `submit`).
