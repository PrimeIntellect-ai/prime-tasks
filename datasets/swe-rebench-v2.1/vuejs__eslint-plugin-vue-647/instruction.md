Rule Proposal: `valid-v-bind-sync`
**Please describe what the rule should do:**

This rule checks `.sync` modifier with `v-bind`.
Most checking of this rule will do the same check as `vue/valid-v-model`.

[Custom Events `.sync` Modifier](https://vuejs.org/v2/guide/components-custom-events.html#sync-Modifier)

**What category of rule is this? (place an "X" next to just one item)**

[ ] Enforces code style
[X] Warns about a potential error
[ ] Suggests an alternate way of doing something
[ ] Other (please specify:)

**Provide 2-3 code examples that this rule will warn about:**

```vue
<TheComponent v-bind:title.sync="foo + bar" />
<input v-bind:title.sync="foo"/>
<div v-for="todo in todos">
  <TheComponent v-bind:title.sync="todo" />
</div>
```

**Why should this rule be included?**

The `.sync` modifier behaves similarly to v-model, so the same problem may get into it.

I would like to ask your opinion whether this check should be a separate rule or included in `valid-v-bind`.

### Additional contract requirements

- The rule is named `valid-v-bind-sync` and is exposed as the module `lib/rules/valid-v-bind-sync.js` (rule id `vue/valid-v-bind-sync`).
