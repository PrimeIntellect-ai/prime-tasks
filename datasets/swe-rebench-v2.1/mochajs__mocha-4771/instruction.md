🚀 Feature: Possibility to return 0 exit code when tests run successfully even with fails
**Is your feature request related to a problem or a nice-to-have?? Please describe.**
A clear and concise description of what the problem is. E.g. I'm always frustrated when [...]

Sometimes it is useful to separate situations when tests run successfully, and there is no infrastructure or runtime problems, and when there are some runtime problems.
Possibility to return non-zero exit code only on infrastructure or runtime problems make easier integration with different toolchain.

**Describe the solution you'd like**
A clear and concise description of what you want to happen.

Flag, something like `failOnFailingTests` like in Karma (https://github.com/karma-runner/karma/blob/master/docs/config/01-configuration-file.md#failonfailingtestsuite).
- 0 exit code when tests run successfully
- 1 exit code when something went wrong

**Describe alternatives you've considered**
A clear and concise description of any alternative solutions or features you've considered.

Karma
https://github.com/karma-runner/karma/blob/master/docs/config/01-configuration-file.md#failonfailingtestsuite

**Additional context**
Add any other context or screenshots about the feature request here.

### Additional contract requirements

- Add a CLI flag `--pass-on-failing-test-suite` that accepts a boolean value and defaults to `false`. When it is `true`, Mocha exits with code `0` even if the test suite contains failing tests; when it is `false`, normal exit-code handling applies. Infrastructure problems (for example, no test files being found) must still produce a non-zero exit code.
- Add a public method `Mocha.prototype.passOnFailingTestSuite(passOnFailingTestSuite = false)` on the `Mocha` class in `lib/mocha.js`. It sets the `passOnFailingTestSuite` option on the instance to the given boolean value and returns the `Mocha` instance for chaining.
- Runtime problems, such as an exception while loading a test file that prevents the suite from running, must retain a nonzero exit status when the option is enabled. This differs from ordinary test failures reported by the runner.
