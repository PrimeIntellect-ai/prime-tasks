list is not compatible with array constructor
- You can do new Array(4) to generate an array with 4 empty items
- Doing the same with list caused an error
- This broke lodash.deepclone and caused a very confusing error for me

### Additional contract requirements

- The module `lib/list.js` exports a constructor `List`.
- `new List(4)` — passing a number as the first argument — creates an empty list of length `4` without throwing, mirroring `new Array(4)`.
- The value returned by `new List(4)` is an instance of `List` and is also an instance of `Array`.
- When the item type argument is omitted, the list's `itemType` is `undefined`.
- The list's `toJSON()` method returns a plain array reflecting the list contents, which for a length-4 list is `[undefined, undefined, undefined, undefined]`.
