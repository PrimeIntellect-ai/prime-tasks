no-shadow-restricted-names doesn't check destructuring
**Tell us about your environment**

* **ESLint Version:** master
* **Node Version:** -
* **npm Version:** -

**What parser (default, Babel-ESLint, etc.) are you using?**

- default

**Please show your full configuration:**
**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
/*eslint no-shadow-restricted-names: error */

function f1() {
    var undefined = 1
}

function f2() {
    var [undefined] = [1]
}

function f3() {
    var {undefined} = {undefined: 1}
}
```

[Online demo](https://eslint.org/demo/#eyJ0ZXh0IjoiLyplc2xpbnQgbm8tc2hhZG93LXJlc3RyaWN0ZWQtbmFtZXM6IGVycm9yICovXHJcblxyXG5mdW5jdGlvbiBmMSgpIHtcclxuICAgIHZhciB1bmRlZmluZWQgPSAxXHJcbn1cclxuXHJcbmZ1bmN0aW9uIGYyKCkge1xyXG4gICAgdmFyIFt1bmRlZmluZWRdID0gWzFdXHJcbn1cclxuXHJcbmZ1bmN0aW9uIGYzKCkge1xyXG4gICAgdmFyIHt1bmRlZmluZWR9ID0ge3VuZGVmaW5lZDogMX1cclxufVxyXG4iLCJvcHRpb25zIjp7InBhcnNlck9wdGlvbnMiOnsiZWNtYVZlcnNpb24iOjgsInNvdXJjZVR5cGUiOiJtb2R1bGUiLCJlY21hRmVhdHVyZXMiOnt9fSwicnVsZXMiOnt9LCJlbnYiOnt9fX0=)

**What did you expect to happen?**

There are three warnings.

**What actually happened? Please include the actual, raw output from ESLint.**

There is a warning.

----

- I found it in making #10429.
- Maybe we can merge that rule to the [no-shadow](https://eslint.org/docs/rules/no-shadow) rule.
