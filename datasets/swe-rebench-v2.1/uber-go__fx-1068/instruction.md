Disallow using In/Out structs with From/As annotations
In #1053, we eased up the requirement for function signature for applying annotations to allow using In/Out structs with ResultTags/ParamTags. This had an unintended change in behavior where users are now able to use In/Out structs with From/As annotations. For example, the below code used to error out:
```
type Foo interface { ... }
type Bar struct { ... } // Bar implements Foo
struct Res {
  fx.Out

  ABar Bar
}
fx.Annotate(
  func() Res { ... },
  fx.As(new(Foo)),
)
```
Currently the code above applies the As annotation to `ABar` field and transforms the target function's signature accordingly. However, this was an unintended change in behavior, and we should have a design discussion about whether we actually want this before cutting a new release. Since it will require a breaking change to disable this after a new release is cut, I think the safe approach is to disable this for now and enable it after having decided that this is indeed what we want.
