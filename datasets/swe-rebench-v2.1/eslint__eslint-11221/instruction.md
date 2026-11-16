Stop reporting warning as errors when using tap reporter
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for requesting a change that is not a bug fix, rule change, or new rule. If you are here for another reason, please see below:

    1. To report a bug: https://eslint.org/docs/developer-guide/contributing/reporting-bugs
    2. To request a rule change: https://eslint.org/docs/developer-guide/contributing/rule-changes
    3. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**The version of ESLint you are using.**
2.7.0

**The problem you want to solve.**
I am a sass-lint user (which relies on eslint-formaters)
When using the tap formatter, all messages are flagged as `not ok` no matter their severity. Messages with severity of 1 should be flagged as `ok` and should contain the warning message. I feel like it's odd to have a failing test result despite all tests are passing but containing some warnings.
However, this seems to be the expected behavior according to tests written in the project.

* Already reported here but closed because of inactivity: https://github.com/eslint/eslint/issues/6916

**Your take on the correct solution to problem.**
The issue is located in this file: https://github.com/eslint/eslint/blob/master/lib/formatters/tap.js#L53
[HIDDEN]

**Are you willing to submit a pull request to implement this change?**
Definitely, I just wanted to be sure this actual problem was not something "by design"

Thanks!

### Additional contract requirements

- A file whose messages all have severity 1 (warnings) must be reported as `ok` in the TAP output, and each of those warning messages must still appear in that file's diagnostics.
- A file that has at least one message with severity 2 (error) must be reported as `not ok`, even when it also has warnings.
