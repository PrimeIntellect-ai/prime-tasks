click-event-has-key-events doesn't always pick up click directive
A co-worker noticed some inconsistency on when this rule throws an error. In our particular use case, these two versions throw the linting error as expected:

```vue
<button @click.prevent="isExpanded = !isExpanded">
```

```vue
<button @click.prevent="toggleIsExpanded()">
```

However, this one doesn't throw the linting error.

```vue
<button @click.prevent="toggleIsExpanded">
```

This is in Vue 3, for what it's worth.
