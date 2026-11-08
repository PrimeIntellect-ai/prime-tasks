Add Support for RegExp match indices
<!--
    ESLint adheres to the Open JS Foundation Code of Conduct:
    https://eslint.org/conduct

    This template is for requesting a change that is not a bug fix, rule change, or new rule. If you are here for another reason, please see below:

    1. To report a bug: https://eslint.org/docs/developer-guide/contributing/reporting-bugs
    2. To request a rule change: https://eslint.org/docs/developer-guide/contributing/rule-changes
    3. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    4. If you have any questions, please stop by our chatroom: https://eslint.org/chat

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->



**The version of ESLint you are using.**

7.27.0

**The problem you want to solve.**

Support RegExp match indices officially, as it has reached stage-4.
refs:
https://github.com/tc39/proposals/blob/master/finished-proposals.md
https://github.com/tc39/proposal-regexp-match-indices

**Your take on the correct solution to problem.**

- [x] Ecma262 update: tc39/ecma262#1713
- [x] Acorn update: acornjs/acorn#1039
- [x] `regexpp`update: https://github.com/mysticatea/regexpp/pull/22
- [x] `espree` update: https://github.com/eslint/espree/pull/505
- [ ] `eslint` update: #14653

[HIDDEN]

**Are you willing to submit a pull request to implement this change?**

I will submit a pull request.

### Additional contract requirements

- The `no-invalid-regexp` rule must recognize `d` as a valid RegExp flag.
- The `no-empty-character-class` rule must continue to report empty character classes in RegExp literals using the `d` flag and not report non-empty character classes.
