Imports are not typechecked
**Describe the bug**
Imported files are not typechecked by the interpreter

**To Reproduce**
```
$echo "1 : Str" > bad.ncl
$nickel -f bad.ncl typecheck
error: Incompatible types
  ┌─ nickel/bad.ncl:1:1
  │
1 │ false : Num
  │ ^^^^^ this expression
  │
  = The type of the expression was expected to be `Num`
  = The type of the expression was inferred to be `Bool`
  = These types are not compatible

$nickel typecheck <<< 'let _ign = import "bad.ncl" in 0'
$
```

**Expected behavior**
The typechecker should transitively typecheck imports.

**Additional context**
The problem is that typechecking is done before program transformations, including import resolution, so the typechecker can't have access to the actual content of imports. A corresponding test should have caught that but for some reason it "cheated" and applied program transformations before typechecking. [HIDDEN] In the longer term, we probably don't want to traverse the whole term in full just for imports, and may interleave import resolution with either typechecking or parsing.
