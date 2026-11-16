`vue/component-name-in-template-casing`: ignore `<component>` built-in element
<!--
  Before proposing rule changes, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/vuejs/eslint-plugin-vue/issues?q=is%3Aopen+is%3Aissue+label%3A%22new+rule+proposition%22
-->

**What rule do you want to change?**

- `vue/component-name-in-template-casing`

**Does this change cause the rule to produce more or fewer warnings?**

It will provide one fewer warning/error, because it will handle an edge-case.

**How will the change be implemented? (New option, new default behavior, etc.)?**

The change will treat `<component>` as an element, not a component.

The `vue/component-name-in-template-casing` rule enforces pascal-cased component names. This will also enforce `<component>` to be written as `<Component>`, which is not correct. Technically, `<component>` is not a component, but an element.

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
The following code will be valid:
```vue
<template>
  <component is="div" />
</template>
```

**What does the rule currently do for this code?**

It will enforce `<component>` to be pascal-cased as `<Component>`:

```vue
<template>
  <Component is="div" />
</template>
```

**What will the rule do after it's changed?**

- Keep `<component>` as-is.

**Additional context**
<!-- Add any other context or screenshots about the feature request here. -->


As the [Vue docs state](https://vuejs.org/api/built-in-special-elements.html):

> [!NOTE]
> `<component>`, `<slot>` and `<template>` are component-like features and part of the template syntax. They are not true components and are compiled away during template compilation. As such, they are conventionally written with lowercase in templates.

The issue came up working with [`@antfu/eslint-config`](https://github.com/antfu/eslint-config).
Related PR:
- https://github.com/antfu/eslint-config/pull/291
