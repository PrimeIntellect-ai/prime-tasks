prefer-destructuring should not check non-numeric indexes
**Tell us about your environment**

* **ESLint Version:** 4.14.0
* **Node Version:** 9.3.9
* **npm Version:** 5.6.0

**What parser (default, Babel-ESLint, etc.) are you using?** default

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

```json
{
  "parserOptions": {
    "ecmaVersion": 6,
    "sourceType": "module"
  },

  "extends": [
    "airbnb-base"
  ],

  "rules": {
    "class-methods-use-this": "off",
    "import/no-extraneous-dependencies": ["off", {"devDependencies": ["webpack-config/*.js"]}],
    "no-prototype-builtins": "off",
    "no-param-reassign": [0],
    "prefer-default-export": "off"
  }
}
```

</details>

**What rule do you want to change?**  prefer-destructuring

**Does this change cause the rule to produce more or fewer warnings?**  Fewer

**How will the change be implemented? (New option, new default behavior, etc.)?** New default behavior

**Please provide some example code that this change will affect:**

```js
const INTEGER_WORDS = {
  one: 1,
  two: 2,
  three: 3,
  four: 4,
 };

let num = 1;
num = INTEGER_WORDS[num];
```

**What does the rule currently do for this code?**

Generates a warning for `num = INTEGER_WORDS[num];`

**What will the rule do after it's changed?**

It will ignore array indexes/keys that are not constants. I would argue this should **always** be the case, as it must be considered bad practice to destructure from a computed index or key.
