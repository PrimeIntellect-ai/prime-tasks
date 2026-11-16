Another unicode "double-escaping" bug
We (Framer) have run into this issue recently where unicode chars are double-escaped in JSX attributes, see the PR with a failing test for it https://github.com/swc-project/swc/pull/2012

```tsx
<Bla title="Ú"/>
```
is being transformed to, note the double backslash:
```tsx
React.createElement(Bla, {
    title: "\\xda"
});
```

### Additional contract requirements

- For `<Bla title="Ú"/>`, the transformed output must be exactly `React.createElement(Bla, {\n    title: "\xda"\n});`.
- For the JSX attribute value `wôw`, emit the output string literal as `w\xf4w` (with a single backslash before `xf4`).
