prefer-namespace-keyword triggers on "declare global {"
### Code:
```ts
declare global {
  interface Window {
    Vue: VueConstructor
  }
}
```

### Error:
```
  1:1  error  Use 'namespace' instead of 'module' to declare custom TypeScript modules  typescript/prefer-namespace-keyword
```
