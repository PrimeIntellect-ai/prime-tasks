`updateIn` throw `Uncaught TypeError: keyPath.slice is not a function` for ArrayLike that does not implement `slice` if the keyPath can not update
## Description

The `updateIn` function does call [`coerceKeyPath`](https://github.com/immutable-js/immutable-js/blob/96bf1f9721abf3e18c874400930dd6764d8116b9/src/functional/updateIn.js#L19) on the keyPath.

The coerceKeyPath does check [if the keyPath is an "ArrayLike"](https://github.com/immutable-js/immutable-js/blob/main/src/utils/coerceKeyPath.ts#L5). If true, the value is kept.

[HIDDEN]



Here is the implementation of `isArrayLike`: https://github.com/immutable-js/immutable-js/blob/main/src/utils/isArrayLike.ts

## Reproductible example


Define the custom array
```ts
class CustomArrayLike<T> implements ArrayLike<T> {
  readonly length: number;
  readonly [n: number]: T;

  constructor(length: number) {
    this.length = length;
    for (let i = 0; i < length; i++) {
      this[i] = undefined as any;
    }
  }

  // Define other methods if needed, but do not include the `slice` method
  // For example, you can define a method to set values
  set(index: number, value: T): void {
    if (index >= 0 && index < this.length) {
      this[index] = value;
    } else {
      throw new RangeError('Index out of bounds');
    }
  }

  // Define a method to get values
  get(index: number): T {
    if (index >= 0 && index < this.length) {
      return this[index];
    } else {
      throw new RangeError('Index out of bounds');
    }
  }
}
```

Code that throws
```ts
// create an ArrayLike
const customArray = new CustomArrayLike<number>(2);
customArray.set(0, 10);
customArray.set(1, 20);

// code that works perfectly
Immutable.updateIn({ 10 :{ 20 : 'a' }}, customArray2, (v) => `${v.toUpperCase()}`)
// does output { 10 :{ 20 : 'A' }}


Immutable.updateIn({ 10 : 'a' }, customArray2, (v) => `${v.toUpperCase()}`)
// does throw Uncaught TypeError: keyPath.slice is not a function
```

### Additional contract requirements

- When `updateIn` encounters a non-data-structure value before completing the key path, it must report `Cannot update within non-data-structure value in path [10]: a` for the custom ArrayLike case and `Cannot update within non-data-structure value in path ["a","b","c"]: 10` for the existing string-key case.
