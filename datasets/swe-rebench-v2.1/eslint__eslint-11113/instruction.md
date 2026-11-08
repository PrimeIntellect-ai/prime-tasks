False negative for camelcase with ignoreDestructuring
**Tell us about your environment**

* **ESLint Version: `5.9.0` **
* **Node Version: `11.0.0` **
* **npm Version: `6.4.1` **

**What parser (default, Babel-ESLint, etc.) are you using?**

default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

```js
camelcase: [2, {ignoreDestructuring: true}]
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

minimal working example to reproduce (yes, it's a silly example):

```js
var { [{category_id: 123}]: categoryId } = query;
```

**What did you expect to happen?**

Reported `camelcase` error for `category_id`.

**What actually happened? Please include the actual, raw output from ESLint.**

No error was reported

**Are you willing to submit a pull request to fix this bug?**

yep 😸
