Function validators only work if they return promises
**Describe the bug**
Due to the change in [6c67c95](https://github.com/mattallty/Caporal.js/commit/6c67c95) validator functions that return a value, rather than a promise, cause the option to be set to undefined [HIDDEN]

**To Reproduce**
1. Create an option with a function validator. For example the simple example below:
```js
function list(value: any): string[] {
    if (typeof value !== 'string') {
        throw new Error(`Invalid value: '${value}'`);
    }
    return value.split(',');
}
```
2. Run the command with the option set, the value comes out as undefined.

**Expected behavior**
My understanding is that the previous change should not have required validator functions to use promises as the examples in the README still return values directly. As such, validator functions that return values rather than promises should also function as they did previously.

**Environment informations (please complete the following information):**
 - OS: Mac
 - OS version: Mojave
 - Shell: Bash
 - Caporal version: 1.2.0

### Additional contract requirements

- When a function validator returns a value synchronously, that value must be supplied as the option value to the command action, rather than `undefined`.
