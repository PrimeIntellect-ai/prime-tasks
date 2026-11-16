[BUG] Prefix from tailwind.config.js not working with named groups
**Describe the bug**
A colleague of mine discovered this issue. We use the ESlint plugin at work and have a shared component library using a tailwind with a prefix to avoid collisions with other tailwind projects. While developing a new feature, we wanted to use the recently introduced syntax for named groups, but ESlint kept nagging about a non-existent class.
I looked into the code for `no-custom-classname`, and [HIDDEN] I believe this is the issue.

**To Reproduce**
```
// HTML
<div class="tw-group/edit">
  <div class="group-hover/edit:tw-text-red-500">Some content</div>
</div>


// tailwind.config.js
/** @type {import('tailwindcss').Config} */
module.exports = {
  prefix: "tw-"
}
```

The plugin will report a false positive unknown class name `tw-group/edit` and `group-hover/edit:tw-text-red-500`

**Expected behavior**
Support the specified prefix specified inside the `tailwind.config.js` together with the named groups and peer syntax.

### Additional contract requirements

- When a Tailwind prefix is configured, named group and peer markers using that prefix must not be reported as unknown classes.
- Prefixed utility classes used in named group and peer variants must be recognized.
