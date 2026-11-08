[BUG] Non-ASCII whitespace should not be treated as class separator
**Describe the bug**
It is a common mistake among Japanese developers to mistakenly insert an Ideographic Space (U+3000) in place of a normal space character (U+0020).
Example:

```jsx
<div className="px-1　py-2">notice that the space between px-1 and py-2 is a U+3000</div>
```

According to the relevant spec, `px-1[U+3000]py-2` is treated as one class name, not two separated by the space. Only ASCII whitespaces are treated as separators. Therefore, `px-1[U+3000]py-2` is not recognized as a Tailwind class by browsers and it does not have any effect. I would like this plugin to catch this kind of mistake.

However, `eslint-plugin-tailwindcss` considers `px-1[U+3000]py-2` as two classes (`px-1` and `py-2`) so it cannot catch this mistake.

**To Reproduce**
Steps to reproduce the behavior:

1. Enable the `no-custom-classname` rule
2. Run the rule against `<div className="px-1　py-2">notice that the space between px-1 and py-2 is a U+3000</div>`
3. Currently you get no error.

**Expected behavior**
The `no-custom-classname` rule should complain that `px-1　py-2` is not a valid Tailwind classname.

**Screenshots**

**Environment (please complete the following information):**
 - OS: macOS
 - Softwares + version used:
     - `tailwind@3.3.2`
     - `eslint-plugin-tailwindcss@3.12.0`

**Additional context**
- `prettier-plugin-tailwindcss` seems to have the same issue.
  - https://github.com/tailwindlabs/prettier-plugin-tailwindcss/pull/166

**eslint config file or live demo**
