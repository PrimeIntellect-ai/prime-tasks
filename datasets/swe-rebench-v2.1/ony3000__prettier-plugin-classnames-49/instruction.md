Component composition with dot notation is not supported.
## Dependency information
TypeScript
React
Prettier 3.2
prettier-plugin-classnames 0.6.3

## Steps to reproduce

```javascript
export const Overlay = () => {
  return (
    <Dialog.Overlay className="bg-popover backdrop-opacity-disabled focus:ring-0 fixed inset-0 z-50 h-screen w-screen" />
  );
};
```

## The current behavior
The className of the Dialog.Overlay is completely ignored.

## The expected behavior
The component classes wrapped based on the printWidth option.
