monorepo-run-tests not detecting file change in the root workspace
Hi, is there a way to set all tests to run when a file in root workspace changes.

e.g when you change something in `setupTest.js` which is set in `jest.config.js`
Making a change in setupTest.js does not trigger all tests, which it should in my opinion.
```
const commonProjectConfig = {
  globals: {
    __DEV__: true,
  },
  timers: "fake",
  setupFilesAfterEnv: [path.join(__dirname, "scripts", "setupTest.js")],
  transform: {
    "^.+\\.[jt]sx?$": "babel-jest",
  },
};
```

### Additional contract requirements

When a shared Jest setup file configured by the root Jest configuration changes, the monorepo test runner must run the full test suite rather than only tests associated with affected workspaces.
