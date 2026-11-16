Rule: Exception should not be created without being thrown
Implements [RSPEC-3984](https://jira.sonarsource.com/browse/RSPEC-3984).

Detecting the pattern "new xxxxxError(....);" should be enough in JS.

### Additional contract requirements

Report a standalone JavaScript expression statement that constructs an exception whose name ends in `Error` without throwing it. Do not report exception constructions used as values or constructions that are explicitly thrown. Implement and register the detector as the JavaScript rule for RSPEC-3984.
