Improve "Unknown module field" error message
I think the error message we get when trying to access a module function that doesn't exist could be improved. Right now it looks like this:

![Screenshot 2024-08-19 alle 20 13 49](https://github.com/user-attachments/assets/3ab2c635-e2c1-4faf-9e61-b26a2f7f629f)

Calling it "module field" strikes me as a bit odd, I've never heard this term before. Maybe it could be worded a bit differently:

```diff
+error: Unknown module function
-error: Unknown module field
   ┌─ /Users/giacomocavalieri/Documents/progetti/ssg/build/packages/jot/src/jot.gleam:20:11
   │
20 │       dict.update(attributes, key, fn(previous) {
   │           ^^^^^^^

+The module `gleam/dict` does not have a `update` function.
-The module `gleam/dict` does not have a `update` field.
```

### Additional contract requirements

The accepted wording for the improved diagnostic is `Unknown module value`
(replacing `Unknown module field`), because that is how the value is referred to
in the error message itself. When the module does not have the named value, the
message must be `The module \`{module_name}\` does not have a \`{name}\` value.`

The new title applies to every unknown module value, not only to functions. In
particular, it must also be used when a type is imported as a value, and when a
value that is private to its module is accessed.
