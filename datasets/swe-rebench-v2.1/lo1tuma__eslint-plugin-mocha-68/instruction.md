Rule proposal: enforce it() description to start with "should"
Would it make sense to enforce having descriptive test names by warning if `it()` description does not start with "should". Example of violation:

```
it("I want to test something", function () {
  // ...
});
```

Valid usage:

```
it("should test something", function () {
  // ...
});
```

Thanks.

### Additional contract requirements

The rule must be wired into the plugin and documented:

- `index.js` must expose the rule under the name `valid-test-description`.
- A documentation file `docs/rules/valid-test-description.md` must exist, and the documentation index `docs/rules/README.md` must contain a link entry of the exact form `* [valid-test-description](valid-test-description.md) - <description>`.
