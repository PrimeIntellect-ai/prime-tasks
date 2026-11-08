Problem with internals.at
Hi

I am having a problem with this line https://github.com/hapijs/code/blob/master/lib/index.js#L435, due to the value of "const at". Sometimes the value is null meaning the return value from function throws an error and then shows "thrown errors in test" message in tests being run by lab.

### Additional contract requirements

- When a failed assertion rethrows an Error whose stack is unavailable, its `at` property must be `undefined`.
