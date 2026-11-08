Logical border color properties does not work with generic border color
### Describe the bug

Using [logical border color properties](https://tailwindcss.com/docs/border-color#using-logical-properties) with a more general property does not work (see below). The more specific property completely removes the generic property.

### To Reproduce

https://codesandbox.io/p/sandbox/happy-field-y446v2
```ts
twMerge('border-blue border-r-red')  // "border-blue border-r-red" (correct)
twMerge('border-blue border-e-red')  // "border-e-red"
twMerge('border-blue border-s-red')  // "border-s-red"
```
### Expected behavior

`twMerge('border-blue border-e-red')` should return `"border-blue border-e-red"` and so on.

### Environment

-   tailwind-merge version: 2.5.2
