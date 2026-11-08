func-name-matching: New option for property descriptors to match against property name
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for requesting a rule change. If you are here for another reason, please see below:

    1. To report a bug: https://eslint.org/docs/developer-guide/contributing/reporting-bugs
    2. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**What rule do you want to change?**

func-name-matching

**Does this change cause the rule to produce more or fewer warnings?**

Sometimes more, sometimes fewer. See examples.

**How will the change be implemented? (New option, new default behavior, etc.)?**

New options: `considerPropertyDescriptor: true` (false by default).

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```js
Object.defineProperty(model, 'key', {
  value: function key() {
    //
  }
});

Object.defineProperties(model, {
  key: {
    value: function key() {
      //
    }
  }
});

Object.create(Foo.prototype, {
  key: {
    value: function key() {
      //
    }
  }
});
```

**What does the rule currently do for this code?**

All three have errors: "Function `key` should match property name 'value'."

**What will the rule do after it's changed?**

If `{ considerPropertyDescriptor: true }` is provided in configuration, all 3 examples should pass.

However, examples like these should then start to be warned:

```js
Object.defineProperty(model, 'key', {
  value: function value() {  // Function name `value` should match property name `key`.
    //
  }
});

Object.defineProperties(model, {
  key: {
    value: function value() {  // Function name `value` should match property name `key`.
      //
    }
  }
});

Object.create(Foo.prototype, {
  key: {
    value: function value() {  // Function name `value` should match property name `key`.
      //
    }
  }
});
```

-------

This is another attempt to propose the same thing as #7423. Unfortunately, there were some process hiccups and the contributor no longer seems interested. So I want to carry it forward.

I'll champion.
