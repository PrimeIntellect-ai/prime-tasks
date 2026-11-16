no-conditional-expect warns when using extended matchers in a condtional
If you're building up, for example, the expected results of a thing, and do something like:

```javascript
const expected = traffic.bodies.map((b) => {
  if (typeof(b) === 'string') {
    return expect.objectContaining({
      message: b
    , timestamp: expect.stringMatching(/^\d{4}-\d{2}-\d{2}T/)
    })
  } else {
    return b
  }
})
```

The rule will trigger for using expect inside the conditional, even though you're not actually doing the "real" expect call here.  I would expect (ha ha) this rule to not trigger in this scenario.

![CleanShot 2024-06-25 at 10 41 08@2x](https://github.com/playwright-community/eslint-plugin-playwright/assets/6078/cae45984-bdc4-4341-a01d-020a02e46460)
