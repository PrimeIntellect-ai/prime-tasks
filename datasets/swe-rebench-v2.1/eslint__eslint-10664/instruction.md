no-restricted-globals rule crashes with 'hasOwnProperty' as restricted global
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are here for another reason, please see below:

    1. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a rule change: https://eslint.org/docs/developer-guide/contributing/rule-changes
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** v5.2.0
* **Node Version:** v8.11.1
* **npm Version:** v5.6.0

**What parser (default, Babel-ESLint, etc.) are you using?** default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
	"rules": {
		"no-restricted-globals": ["error", "hasOwnProperty"],
	}
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
module.exports = obj => hasOwnProperty(obj, 'name');
```

**What did you expect to happen?**
Should get a warning for using the global "hasOwnProperty".

**What actually happened? Please include the actual, raw output from ESLint.**

```
restrictedGlobalMessages.hasOwnProperty is not a function
TypeError: restrictedGlobalMessages.hasOwnProperty is not a function
    at isRestricted (/Users/richard/github/website-backend/playosmo-js/node_modules/eslint/lib/rules/no-restricted-globals.js:97:45)
    at Program.scope.variables.forEach.variable (/Users/richard/github/website-backend/playosmo-js/node_modules/eslint/lib/rules/no-restricted-globals.js:106:50)
    at Array.forEach (<anonymous>)
    at Program (/Users/richard/github/website-backend/playosmo-js/node_modules/eslint/lib/rules/no-restricted-globals.js:105:33)
    at listeners.(anonymous function).forEach.listener (/Users/richard/github/website-backend/playosmo-js/node_modules/eslint/lib/util/safe-emitter.js:45:58)
    at Array.forEach (<anonymous>)
    at Object.emit (/Users/richard/github/website-backend/playosmo-js/node_modules/eslint/lib/util/safe-emitter.js:45:38)
    at NodeEventGenerator.applySelector (/Users/richard/github/website-backend/playosmo-js/node_modules/eslint/lib/util/node-event-generator.js:251:26)
    at NodeEventGenerator.applySelectors (/Users/richard/github/website-backend/playosmo-js/node_modules/eslint/lib/util/node-event-generator.js:280:22)
    at NodeEventGenerator.enterNode (/Users/richard/github/website-backend/playosmo-js/node_modules/eslint/lib/util/node-event-generator.js:294:14)
```

[HIDDEN]
