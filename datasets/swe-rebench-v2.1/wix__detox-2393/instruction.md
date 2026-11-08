Pick tests by the name
**Problem**
Detox allows run specific tests by passing a path/fileName only. E.g. `detox test e2e/testSuite.spec.js`.
There is no way to run a specific test list from the suite. E.g. `testSuite.spec.js` script is
```
it('test name 1', () => {...});
it('test name 2', () => {...});
it('test name 3, () => {...});
it('test name 4, () => {...});
...
```
I want to run `test name 1` and `test name 3` tests only (I'm not talking about development stage where I can use `it.only`)

**Usage**
I have a huge number of e2e tests that take a lot of time. I can't run all of them on every PR/commit coz it will significantly increase development cycle time. Instead, I want to create a specific list of the tests that will run (kind of sanity suite).

**Solution**
If Detox runs with Jest, I can run a specific list of the tests by their name using `--testNamePattern` (https://jestjs.io/docs/en/cli#--testnamepatternregex). Currently, it's occupied by a regexp that Detox sets `--testNamePattern=^((?!:android:).)*$` for iOS ad `--testNamePattern=^((?!:ios:).)*$` for Android, so the value I pass is ignored.

### Additional contract requirements

- A custom pattern supplied as either `-t` or `--testNamePattern` must replace, not combine with, Detox's platform-specific `--testNamePattern` filter; for example, `-t customPattern` must be forwarded as `--testNamePattern customPattern`.
