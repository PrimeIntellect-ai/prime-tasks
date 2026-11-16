Object-shorthand breaks when a dynamic key has a dot
<!--
This template is for bug reports. If you are reporting a bug, please continue on. If you are here for another reason, please see below:

1. To propose a new rule: http://eslint.org/docs/developer-guide/contributing/new-rules
2. To request a change: http://eslint.org/docs/developer-guide/contributing/changes
3. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

FYI, this is a dupe of #8351, but just including more information:

**Tell us about your environment**
* **ESLint Version:**
3.19.0
* **Node Version:**
7.9.0
* **npm Version:**
4.2.0

**What parser (default, Babel-ESLint, etc.) are you using?**
babel-eslint

**Please show your full configuration:**

<!-- Paste your configuration below: -->
```
'object-shorthand': [2, 'always', {'ignoreConstructors': true}],
```

**What did you do? Please include the actual source code causing the issue.**

<!-- Paste the source code below: -->

~~const keys = {~~
~~first: 'first',~~
~~second: 'second',~~
~~};~~

~~const o = {~~
~~[keys.first]: true,~~
~~[keys.last]: true,~~
~~};~~


```js
const actionHandlers = {
	[actionTypes.UPDATE_COLLAPSED_ENTRIES]: state => true
};
```


**What did you expect to happen?**
For it not to error out.

**What actually happened? Please include the actual, raw output from ESLint.**
It through an error:
```
TypeError: Cannot read property 'charAt' of undefined
    at isConstructor (/Users/ncavanaugh/Dev/git/check-source-formatting/node_modules/eslint/lib/rules/object-shorthand.js:120:35)
    at EventEmitter.Property:exit (/Users/ncavanaugh/Dev/git/check-source-formatting/node_modules/eslint/lib/rules/object-shorthand.js:395:48)
...
```

[HIDDEN]

Let me know if you need more info than the above.

Thanks!

### Additional contract requirements

- With the shown `object-shorthand` configuration, linting a property with a computed dotted member-expression key must not throw an exception.
