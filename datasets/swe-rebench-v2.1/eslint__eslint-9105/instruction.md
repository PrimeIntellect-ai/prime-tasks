Allow arbitrary nodes to be ignored in the `indent` rule
# Problem

People have lots of different indentation preferences, and the `indent` rule can't realistically support all of them. With other rules, we generally encourage people to make a plugin if they want to enforce their specific preferences, which implies disabling the core rule and using the rule from the plugin instead.

However, the `indent` rule is big and complicated, and if a user wants to disable it in favor of their plugin, then the plugin needs to reimplement the entire rule. This adds a very large maintenance burden.

# Proposal

**What rule do you want to change?**

`indent`

**Does this change cause the rule to produce more or fewer warnings?**

By default, it produces the same amount.

**How will the change be implemented? (New option, new default behavior, etc.)?**

This change adds an `ignoredNodes` option to the rule, which is an array of AST selectors. Any nodes matching those selectors will be treated the same way as unknown node types -- the indentation of their direct children will be ignored, but the indentation of nested children will still be enforced relative to each other.

**Please provide some example code that this change will affect:**

```js
/* eslint indent: [
    error,
    4,
    {
        ignoredNodes: ["VariableDeclarator[kind='const']"]
    }
] */

const foo = 1,
      bar = 2,
      baz = 3,
      qux = function() {
          return;
      };
```

**What does the rule currently do for this code?**

The rule reports an error because it enforces a style where `bar`, `baz`, and `qux` are indented incorrectly. (We have gotten several feature requests to allow a style like this.)

**What will the rule do after it's changed?**

The rule will ignore the indentation of `bar`, `baz`, and `qux`, but it will still enforce the alignment of the `return` statement with `qux`. This would allow someone to write a plugin that just checks the indentation of `bar`, `baz`, and `qux`, without reimplementing the indentation logic for anything else.
