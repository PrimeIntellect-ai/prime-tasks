Special Characters Corrupt Formatting
## Dependency information
Here is my config
```js
export default {
  plugins: [
    "prettier-plugin-astro", // ^0.13.0
    "prettier-plugin-tailwindcss", // ^0.5.11
    "prettier-plugin-classnames", // ^0.6.4
    "prettier-plugin-merge", // ^0.6.0
  ],
  trailingComma: "none",
  semi: false,
  printWidth: 100,
  tailwindFunctions: ["tw"],
  customAttributes: ["class", "className", "style", "classList"],
  overrides: [
    {
      files: "*.astro",
      options: {
        parser: "astro",
      },
    },
  ],
};
```

## Steps to reproduce
Format a file with this character '•' (there are others)
`page.astro`
```astro
---
import SettingsLayout from "@layouts/settings.astro";
import SecurityForm from "./_security";
---

<SettingsLayout
  title="Settings • Details"
  class="flex max-w-[1100px] flex-col gap-4 overflow-x-hidden text-left"
>
  <SecurityForm client:only />
</SettingsLayout>
```

## The current behavior
Becomes this
```astro
---
import SettingsLayout from "@layouts/settings.astro";
import SecurityForm from "./_security";
---

<SettingsLayout
  title="Settings • Details"
  class="f"μα"
    " δξξπξκκγαεζμξζμγηκκοιζιζξηιθοημιγνθλ______________________
  γ
  <SecurityForm
  client:only
/>
```
The curruption depends on the character. For example, the string `δξξπξκκγαεζμξζμγηκκοιζιζξηιθοημιγνθλ______________________` is always observed when the character `•` is present.

## The expected behavior
Nothing should happen in this case as the className is not long enough.
