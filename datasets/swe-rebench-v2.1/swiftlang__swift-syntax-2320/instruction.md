MacroSystem should add newline at the end of added members for an empty type
### Description

Given a macro `AddMembers` that does as its name suggests, MacroSystem will currently expand the following:
```
@AddMembers struct Foo {}
```

To:
```
struct Foo {
  func addedMember() {
    ...
  }}
```

Note the lack of a newline after the added member. This usually makes sense as there would already be one, but when there isn't, we should add it.

rdar://116773975

### Additional contract requirements

When a member macro adds members to an empty type declaration, the expanded
source must place each added member on its own line, indented by the configured
indentation width, and must ensure that the closing brace of the type is
preceded by a newline. In particular, expanding

    @AddMembers struct Foo {}

where `AddMembers` provides the single member `var x = 0` must produce exactly

    struct Foo {

      var x = 0
    }

i.e. the first added member is separated from the opening brace by a blank
line, and the closing brace is on its own line. When more than one member is
added, consecutive members are likewise separated by a blank line.
