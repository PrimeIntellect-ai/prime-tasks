require-data-selectors rule should not apply to cy.get('@alias')
Hello,

I was in the midst of updating Cypress related packages, and updated this package to the latest 2.9.0 release. I also realized there's the **require-data-selectors** rule which I recently enabled as a warning. However, now I have a whole bunch of warnings for places where I use aliases, e.g.
```javascript
cy.get('[data-test=a]').as('a'); // this is fine
cy.get('@a'); // this is a warning
```

Minor issue as this is a non-essential rule to us, but I thought for posterity it is worth mentioning.
