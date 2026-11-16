"Inline Variable" action does not work with leading field lookups
Bug with the "inline variable" code refactor action. When in-lining a variable, if the definition body of the variable **starts by referencing a field** then the action breaks the code, by omitting the record.

## main example
```
type Foo {
  Foo(items: List(Int))
}

pub fn main() {
  let myfoo = Foo([])
  let xyz = myfoo.items       // reference any `record.field`, or bigger expressions starting like this
  echo xyz
}
```
In-lining the variable xyz results in this:
```
pub fn main() {
  let myfoo = Foo([])
  echo items                  // expected "echo myfoo.items"
}
```
## what works okay
Wrapping in braces works okay:
```
  let myfoo = Foo([])
  let xyz = {myfoo.items}
  echo xyz
```
Leading with not a field reference works okay:
```
  let myfoo = Foo([])
  let item = list.first(myfoo.items) // fine leading with a module reference
  echo item
```


## Versions

Gleam 1.9.1

VsCode
Version: 1.98.2 (user setup)
Commit: ddc367ed5c8936efe395cffeec279b04ffd7db78
Date: 2025-03-12T13:32:45.399Z
Electron: 34.2.0
ElectronBuildId: 11161602
Chromium: 132.0.6834.196
Node.js: 20.18.2
V8: 13.2.152.36-electron.0
OS: Windows_NT x64 10.0.26100

### Additional contract requirements

- The unused-value warning emitted for a discarded record field access must
  highlight the whole access expression, not only the field identifier. For
  the source

  ```gleam
  pub type Thing {
    Thing(value: Int)
  }

  pub fn main() {
    let thing = Thing(1)
    thing.value
    1
  }
  ```

  the warning message is `This value is never used`, it points at line 8,
  column 3 and underlines all eleven characters of `thing.value`.
