Request: add QUnit.todo support to XUnit reporter
PR #1400 did excellent work supporting [QUnit.todo()](https://api.qunitjs.com/QUnit/test.todo/) support but they missed the [XUnit reporter](https://github.com/testem/testem/blob/master/lib/reporters/xunit_reporter.js).

Requesting this new feature. Thank you.

### Additional contract requirements

- The XUnit reporter writes a `<testsuite>` element whose opening tag lists attributes in this order: `name`, `tests`, `skipped`, `todo`, `failures`, `timestamp`, and `time`.
- The `todo` attribute reports the number of todo tests.
- A test result marked as a todo is reported as a `<todo/>` element inside its `<testcase>`.
