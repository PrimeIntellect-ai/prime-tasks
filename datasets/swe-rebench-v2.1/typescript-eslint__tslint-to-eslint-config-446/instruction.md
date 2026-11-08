Don't log "0 new packages are required"
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 1.0.0-beta
-   ESLint version: N/A
-   Node version: N/A

#### Actual Behavior

After already having run `npx tslint-to-eslint-config` and the recommended `npm install` command:

```
npx tslint-to-eslint-config --prettier

♻ 1875 files of TSLint comment directives converted to ESLint. ♻

⚡ 0 new packages are required for this ESLint configuration. ⚡
  npm install  --save-dev

✅ All is well! ✅
```

#### Expected Behavior

If there are no new packages, don't bother.
