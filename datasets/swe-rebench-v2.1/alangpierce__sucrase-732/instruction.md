`disableESTransform` has unexpected side effects
```js
import { transform } from "sucrase";

const tsCode = `abstract class Test {
    abstract readonly result: string
  }
`;

console.log({
  withESTransform: transform(tsCode, {
    transforms: ["typescript"],
    disableESTransforms: false,
  }).code,

  withoutESTransform: transform(tsCode, {
    transforms: ["typescript"],
    disableESTransforms: true,
  }).code,
});
```

Result:

```js
{
  withESTransform: ' class Test {\n    \n  }\n',
  withoutESTransform: ' class Test {\n      result\n  }\n'
}
```

TypeScript has the same output as the `withESTransform` one, and that's the one I expected: https://www.typescriptlang.org/play?#code/IYIwzgLgTsDGEAJYBthjAgKgU0gg3gLABQCCokM8CU2wAJgPYB2yAnjbgK7IQBcCSgEtmAcxIBfEkA

For context, I'm using `disableESTransforms` because I want to keep the code as close as possible to the source.

It matters to me because my code looks like this:

```typescript
abstract class Parent {
  abstract readonly result: string
}
class Child extends Parent {
  get result() { return 'expected' }
}
console.log(new Child().result) // undefined instead of 'expected'
```
