HTML comments inside svelte markup cause formatting to fail
**Describe the bug**
HTML comments inside svelte markup prevents remaining markup from being formatted.

**To Reproduce**
For example (with `"svelteStrictMode": true`) this:

```svelte
<Component   foo={bar}
      />
<!-- comment -->
<Component   foo={bar}
      />
```
becomes
```svelte
<Component foo="{bar}" />
<!-- comment -->
<Component   foo={bar}
      />
```

<hr/>

Using js comments works, however, they are not syntax highlighted.

```svelte
<Component foo="{bar}" />
// comment
<Component foo="{bar}" />
```

**Expected behavior**
Should get this:
```svelte
<Component foo="{bar}" />
<!-- comment -->
<Component foo="{bar}" />
```

**System:**
 - OS: Windows
 - IDE: VSCode
 - Plugin/Package: "Svelte for VSCode"
