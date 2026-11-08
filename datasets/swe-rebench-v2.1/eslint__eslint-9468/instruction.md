camelcase rule doesn't ignore default parameter assignment when disabled
**Tell us about your environment**

**ESLint Version:** 3.19.0
**Node Version:** 6.9.4
**npm Version:** 3.10.10

**What parser (default, Babel-ESLint, etc.) are you using?** Default

**Please show your full configuration:**

```
module.exports = {
    "extends": "standard",
    "plugins": [
        "standard",
        "promise"
    ],
    "parserOptions": {
      "ecmaVersion": 6
    },
    "env": {
      "node": true
    },
    "rules": {
      "semi": ["error", "always"],
      "camelcase": [2, {"properties": "never"}]
    }
};
```

**What did you do? Please include the actual source code causing the issue.**

Disabling the `camelcase` rule does not appear to respect ES6 default parameter assignment when used with object destructuring syntax.

Here's a simple example:

```
// example.js

function snakeCase ({
  param_1 = 'default value',
  param_2 = 'another default'
} = {}) {
  // do stuff
}

module.exports = snakeCase;

```

**What did you expect to happen?**

Eslint should not care that `param_1` and `param_2` are using snake case instead of camelCase as the rule is disabled

**What actually happened? Please include the actual, raw output from ESLint.**

```
error  Identifier 'param_1' is not in camel case                            camelcase
error  Identifier 'param_2' is not in camel case                            camelcase
```

### Additional contract requirements

- The `properties` option only controls whether object property names are checked. Destructured binding names are checked regardless of this option. For example, with `properties: "never"`, `function foo({ no_camelcased = 'default value' }) {}` still reports `no_camelcased`, and `function foo({ isCamelcased: no_camelcased }) {}` still reports `no_camelcased`, while `var { category_id: category } = query;` reports nothing because only the property name `category_id` is exempt.
- The default value expression on the right-hand side of a destructuring default is not reported as a separate violation, so an identifier is reported at most once. For example, `const no_camelcased = 0; function foo({ camelcased_value = no_camelcased }) {}` reports `no_camelcased` and `camelcased_value`, but not `no_camelcased` twice.


- When reporting `no_camelcased`, the diagnostic must be exactly `Identifier 'no_camelcased' is not in camel case.`
