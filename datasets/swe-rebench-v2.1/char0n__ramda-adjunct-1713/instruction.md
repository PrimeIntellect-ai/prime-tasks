filterIndexed
**Is your feature request related to a problem? Please describe.**

[R.filter](https://ramdajs.com/docs/#filter) doesn't expose index to the predicate function. Let's create a function that does and call it `filterIndexed`.

**Describe the solution you'd like**
```js
filterIndexed((v, idx) => idx === 0, [1, 2, 3); // => [1]
```
Possible implementation
```js
[HIDDEN]
```
**Describe alternatives you've considered**

--

**Additional context**

--
