placeholderData is not transformed by select
**Describe the bug**

`placeholderData` passed to `useQuery`'s option is not transformed by `select` when it exists.

**To Reproduce**

https://codesandbox.io/s/react-query-placeholderdata-with-select-dsvxl


`data.toString()` renders `2020-02-18T15:29:59.326Z` at first.
After 1 second, it renders formatted date like `Fri Feb 19 2021 00:29:59 GMT+0900` as `data` is transformed to Date object by `select` function.

Then replace `placeholderData` to `initialData`. It shows `Wed Feb 19 2020 00:29:59 GMT+0900` and  1 second later `Fri Feb 19 2021 00:29:59 GMT+0900` as both are Date object.

**Expected behavior**

It seems `placeholderData` should be transformed by `select` to keep return type of `data` like `initialData`.
