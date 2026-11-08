Allow custom toggles in vue/require-toggle-inside-transition
<!--
  Before proposing rule changes, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/vuejs/eslint-plugin-vue/issues?q=is%3Aopen+is%3Aissue+label%3A%22new+rule+proposition%22
-->

**What rule do you want to change?**

[vue/require-toggle-inside-transition](https://eslint.vuejs.org/rules/require-toggle-inside-transition.html)

**Does this change cause the rule to produce more or fewer warnings?**

If option is configured, fewer warnings.

**How will the change be implemented? (New option, new default behavior, etc.)?**

I would add a new option to the rule which allows adding additional custom "toggle" directives which will satisfy this check in addition to `v-show` or `v-if`.

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```vue
<transition>
  <dialog v-dialog="visible">...</dialog>
</transition>
```

**What does the rule currently do for this code?**

It flags it as an error, because there is no `v-show` or `v-if` on the `<dialog>`

**What will the rule do after it's changed?**

If the rule is configured to include `v-dialog` as a toggle directive, it will no longer flag this case as an error.

**Additional context**
<!-- Add any other context or screenshots about the feature request here. -->

In the example above, `v-dialog` is a custom directive which shows/hides the element using `close()` and `showModal()`. Transitions are also applied in the directive.

### Additional contract requirements

- The rule accepts an options object with an `additionalDirectives` property: an array of directive names written without the `v-` prefix. Each directive listed there, together with `v-if` and `v-show`, satisfies the requirement that an element inside `<transition>` controls its own display.
- When the rule reports an element, the error message names the allowed directives as a human-readable list. The list includes `v-if`, `v-show`, and every configured additional directive written with its `v-` prefix.
