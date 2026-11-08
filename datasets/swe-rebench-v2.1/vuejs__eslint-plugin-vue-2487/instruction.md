vue/require-toggle-inside-transition - question: should it still be an error with a conditional appear attribute?
<!--
  Before proposing rule changes, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/vuejs/eslint-plugin-vue/issues?q=is%3Aopen+is%3Aissue+label%3A%22new+rule+proposition%22
-->

**What rule do you want to change?**

- vue/require-toggle-inside-transition

**Does this change cause the rule to produce more or fewer warnings?**

- fewer

**How will the change be implemented? (New option, new default behavior, etc.)?**

- new default behaviour - don't give an error when there is a conditional appear attribute on a node

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```vue
<transition :appear="appIsLoaded">
  <div>Something</div>
</transition>
```

**What does the rule currently do for this code?**

- shows an error on the div - "The element inside `<transition>` is expected to have a `v-if` or `v-show` directive"

**What will the rule do after it's changed?**

- not show an error

**Additional context**
<!-- Add any other context or screenshots about the feature request here. -->

We are using a conditional `appear` attribute so that the animation is not shown on the first load of the app, only when navigating between components.

I'm not 100% sure this is a valid use of appear and transition, so I would like to confirm this too.

Thanks!
