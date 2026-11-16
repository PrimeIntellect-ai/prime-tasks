jasmine arrayWithExactContents
Given two arrays:
```ts
const array1 = [3, 1, 2];
const array2 = [1, 2, 3];
```

Input:
```ts
expect(array1).toEqual(jasmine.arrayWithExactContents(array2));
```

should be transformed to:
```ts
expect(array1.sort()).toEqual(array2.sort());
```
