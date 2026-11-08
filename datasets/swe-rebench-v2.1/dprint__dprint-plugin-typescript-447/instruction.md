Extra space in JSX self-closing components
**Describe the bug**

dprint-plugin-typescript version: 0.76.0

It seems like the new `jsx.bracketPosition` setting is adding an extra space to self-closing elements.

**Input Code**
```json
// dprint file
{
    "indentWidth": 4,
    "typescript": {
        "quoteStyle": "alwaysSingle",
        "jsx.quoteStyle": "preferDouble",
        "trailingCommas": "never",
        "jsx.bracketPosition": "sameLine"
    },
    "includes": [
        "**/*.{ts,tsx,js,jsx,cjs,mjs}"
    ],
    "excludes": [
        "**/node_modules",
        "**/*-lock.json"
    ],
    "plugins": [
        "https://plugins.dprint.dev/typescript-0.76.0.wasm"
    ]
}
```

```tsx
<MyComponent someProp={value} />
```

**Expected Output**

```tsx
<MyComponent someProp={value} />
```

**Actual Output**

```tsx
<MyComponent someProp={value}  />
```
