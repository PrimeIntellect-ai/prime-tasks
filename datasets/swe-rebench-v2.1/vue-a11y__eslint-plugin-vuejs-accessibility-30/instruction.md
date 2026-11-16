Skip aria-hidden emojis
```html
<template #label>
  <span aria-hidden>🔽</span>
  Title
</template>
<template #label="{ isOpen }">
  <span aria-hidden>{{ isOpen ? "🔼" : "🔽" }}</span>
  Title
</template>
```
The above results in this message:

> Emojis should be wrapped in <span>, have role="img", and have an accessible description with aria-label or aria-labelledby

If it has an `aria-hidden` it should skip that message. `aria-hidden` completely removes the entire element from the accessibility API. So the role and label will not be seen.
