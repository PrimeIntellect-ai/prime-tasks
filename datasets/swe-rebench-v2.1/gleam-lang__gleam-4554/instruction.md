Renaming a variable doesn't update label shorthands properly
Given this code:
```gleam
pub type Foo {
  Foo(first: Int, second: Int)
}

pub fn example() {
  let foo = Foo(1, 2)
  let second = 3

  Foo(..foo, second:)
}
```
If we rename the variable `second` to be `my_second`, it changes the code to this:
```gleam
pub fn example() {
  let foo = Foo(1, 2)
  let my_second = 3

  Foo(..foo, my_second)
}
```
This is invalid Gleam. It needs to be turned into this:
```gleam
pub fn example() {
  let foo = Foo(1, 2)
  let my_second = 3

  Foo(..foo, second: my_second)
}
```

### Additional contract requirements

Renaming from the label-shorthand use itself must also rename the local variable while preserving the argument label and converting the shorthand argument into an explicit label/value argument.
