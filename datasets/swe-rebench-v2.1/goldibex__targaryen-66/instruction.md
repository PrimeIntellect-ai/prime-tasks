evaluation error in rule should not permit operation
A validation rule such as `".validate": "auth.notAFunction() === false"` should fail.

Failing test: https://github.com/mhuebert/targaryen/blob/rule-evaluation/test/spec/lib/ruleset.js#L196
