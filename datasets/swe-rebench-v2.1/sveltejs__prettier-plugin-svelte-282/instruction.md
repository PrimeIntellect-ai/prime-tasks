Whitespace sensitivity is not ignored with Svelte components
It was indirectly implied in #245 that setting `htmlWhitespaceSensitivity` to `"ignore"` would be respected when formatting Svelte components. However, that doesn't seem to be the case. Please see the following example.

Input:

```jsx
<p><ExternalLink href="https://www.buymeacoffee.com">buy me a coffee</ExternalLink>!</p>
```

Output with `htmlWhitespaceSensitivity: "ignore"`:

```jsx
<p>
    <ExternalLink href="https://www.buymeacoffee.com"
        >buy me a coffee</ExternalLink
    >!
</p>
```

I believe the expected output with `htmlWhitespaceSensitivity: "ignore"` should be:

```jsx
<p>
    <ExternalLink href="https://www.buymeacoffee.com">
        buy me a coffee
    </ExternalLink>!
</p>
```

As far as I can tell, this appears to be a bug as it only occurs with Svelte components. Standard HTML elements seem to be treated correctly. For example, the [`all-elements-ignore-whitespace` test](https://github.com/sveltejs/prettier-plugin-svelte/tree/master/test/formatting/samples/all-elements-ignore-whitespace) demonstrates the correct behavior with `<span>` elements but not Svelte components.
