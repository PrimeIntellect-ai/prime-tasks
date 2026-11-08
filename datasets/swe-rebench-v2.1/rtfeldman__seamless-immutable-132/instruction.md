Should without() accept numeric keys?
I recently ran into an issue where numeric IDs were being used to build and work with an object. This didn't work with the without() function. Not a big deal, but it is inconvenient to worry about "toString()" before using a variable, and other seamless functions seems to handle numeric keys:

```
let o = Immutable({ "foo":"bar", 42:"dog" })
console.log(o.set(42, "cat")) // yep  {42: "cat", foo: "bar" }
console.log(o.without(42))    // nope {42: "dog", foo: "bar" }
console.log(o.without("42"))  // yep  {foo: "bar" }
```
The scenario for me was using an ID from a received JSON object. The sender may store the value as 42 or "42", and ensuring it is a string for this one function is a little inconsistent.

Thanks,
Jim
