no-unused-vars errors with parameters when parameter marked used later
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

* **ESLint Version:** 5.6.1
* **Node Version:** v9.4.0
* **npm Version:** 5.6.0

**What parser (default, Babel-ESLint, etc.) are you using?** babel-eslint

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
	"parser": "babel-eslint",
	"plugins": [
		"babel",
		"react"
	],
	"extends": ["plugin:react/recommended"],
	"rules": {
		"no-unused-vars": 1
	}
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

The eslint-plugin-react rule for `jsx-uses-vars` [marks the `Wrapped` parameter as used](https://github.com/yannickcr/eslint-plugin-react/blob/master/lib/rules/jsx-uses-vars.js#L45).  However, `no-unused-vars` doesn't update the status of `config`.  The default for `no-unused-vars` should not warn on parameters before the first used parameter.

<!-- Paste the source code below: -->
```js
import React from 'react';
import foo from 'foo';

export const AccessibilityDecorator = foo((config, Wrapped) => {
	return class t extends React.Component {
		render () {
			return <Wrapped />;
		}
	};
});
```

<!-- Paste the command you used to run ESLint: -->
```bash
eslint .
```

**What did you expect to happen?**

No warnings.

**What actually happened? Please include the actual, raw output from ESLint.**

```
/Users/.../.../test.js
  4:44  warning  'config' is defined but never used  no-unused-vars

✖ 1 problem (0 errors, 1 warning)
```

Linked issue: yannickcr/eslint-plugin-react#2009
