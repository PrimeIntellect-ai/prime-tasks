linter.verifyAndFix incorrectly requires third argument
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

    1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
    3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** master
* **Node Version:** 8.1.2
* **npm Version:** 5.0.3

**What parser (default, Babel-ESLint, etc.) are you using?**

N/A

**Please show your full configuration:**

N/A

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->
```js
const eslint = require("eslint");
const linter = new eslint.Linter();

linter.verifyAndFix("foo", { rules: { semi: "error" } })
```

**What did you expect to happen?**

I expected an object containing fix info to be returned:

```json
{ "fixed": true, "messages": [], "output": "foo;" }
```

**What actually happened? Please include the actual, raw output from ESLint.**

An error was thrown:

```
TypeError: Cannot read property 'filename' of undefined
    at Linter.verifyAndFix (/path/to/eslint/lib/linter.js:1221:46)
    at repl:1:8
    at ContextifyScript.Script.runInThisContext (vm.js:44:33)
    at REPLServer.defaultEval (repl.js:239:29)
    at bound (domain.js:301:14)
    at REPLServer.runBound [as eval] (domain.js:314:12)
    at REPLServer.onLine (repl.js:433:10)
    at emitOne (events.js:120:20)
    at REPLServer.emit (events.js:210:7)
    at REPLServer.Interface._onLine (readline.js:278:10)
```

It seems like the third "options" argument for `linter.verifyAndFix` is accidentally required. It's optional for `linter.verify`, so it should also be optional for `linter.verifyAndFix`.

As a workaround, one can use:

```js
linter.verifyAndFix(text, config, {});
```
