no-unknown-property does not recognize onClickCapture on <div>
Using eslint-plugin-react v7.31.6

The following code
```tsx
<div onClickCapture={() => {}} />
```
Emits the following error
> Unknown property 'onClickCapture' found eslint ([react/no-unknown-property](https://github.com/jsx-eslint/eslint-plugin-react/tree/master/docs/rules/no-unknown-property.md))

But there are multiple `xxxCapture` events defined in the React for these primitive elements:
https://github.com/DefinitelyTyped/DefinitelyTyped/blob/1beed2ef47be5c1c283132c6cdfbd806ad0fb4ae/types/react/index.d.ts#L1477-L1512
