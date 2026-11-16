oldc vs newc Parsing-Difference: indirection on call
I noticed that the c code produces different results with the old and new c parser

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef long unsigned int (*hStrLenFunc)(const char *str);

int main()
{
    hStrLenFunc strLenFunc = &strlen;
    return (*strLenFunc)("123");
}
```

newc:
```scala
joern> cpg.method("main").call.l
res26: List[Call] = List(
  Call(
    id -> 3074457345618261028L,
    argumentIndex -> 2,
    argumentName -> None,
    code -> "strLenFunc = &strlen",
    columnNumber -> Some(value = 16),
    dispatchType -> "STATIC_DISPATCH",
    dynamicTypeHintFullName -> ArraySeq(),
    lineNumber -> Some(value = 9),
    methodFullName -> "<operator>.assignment",
    name -> "<operator>.assignment",
    order -> 2,
    signature -> "TODO",
    typeFullName -> "<empty>"
  ),
  Call(
    id -> 3074457345618261030L,
    argumentIndex -> 2,
    argumentName -> None,
    code -> "&strlen",
    columnNumber -> Some(value = 29),
    dispatchType -> "STATIC_DISPATCH",
    dynamicTypeHintFullName -> ArraySeq(),
    lineNumber -> Some(value = 9),
    methodFullName -> "<operator>.addressOf",
    name -> "<operator>.addressOf",
    order -> 2,
    signature -> "TODO",
    typeFullName -> "<empty>"
  ),
  Call(
    id -> 3074457345618261033L,
    argumentIndex -> 1,
    argumentName -> None,
    code -> "(*strLenFunc)(\"123\")",
    columnNumber -> Some(value = 11),
    dispatchType -> "STATIC_DISPATCH",
    dynamicTypeHintFullName -> ArraySeq(),
    lineNumber -> Some(value = 10),
    methodFullName -> "",
    name -> "",
    order -> 1,
    signature -> "TODO",
    typeFullName -> "<empty>"
  ),
  Call(
    id -> 3074457345618261034L,
    argumentIndex -> 0,
    argumentName -> None,
    code -> "*strLenFunc",
    columnNumber -> Some(value = 12),
    dispatchType -> "STATIC_DISPATCH",
    dynamicTypeHintFullName -> ArraySeq(),
    lineNumber -> Some(value = 10),
    methodFullName -> "<operator>.indirection",
    name -> "<operator>.indirection",
    order -> 0,
    signature -> "TODO",
    typeFullName -> "<empty>"
  )
)
```

oldc:
```scala
joern> cpg.method("main").call.l
res3: List[Call] = List(
  Call(
    id -> 1000463L,
    argumentIndex -> 2,
    argumentName -> None,
    code -> "strLenFunc = &strlen",
    columnNumber -> Some(value = 16),
    dispatchType -> "STATIC_DISPATCH",
    dynamicTypeHintFullName -> ArraySeq(),
    lineNumber -> Some(value = 9),
    methodFullName -> "<operator>.assignment",
    name -> "<operator>.assignment",
    order -> 2,
    signature -> "TODO",
    typeFullName -> "<empty>"
  ),
  Call(
    id -> 1000465L,
    argumentIndex -> 2,
    argumentName -> None,
    code -> "&strlen",
    columnNumber -> Some(value = 29),
    dispatchType -> "STATIC_DISPATCH",
    dynamicTypeHintFullName -> ArraySeq(),
    lineNumber -> Some(value = 9),
    methodFullName -> "<operator>.addressOf",
    name -> "<operator>.addressOf",
    order -> 2,
    signature -> "TODO",
    typeFullName -> "<empty>"
  ),
  Call(
    id -> 1000468L,
    argumentIndex -> 1,
    argumentName -> None,
    code -> "(*strLenFunc)(\"123\")",
    columnNumber -> Some(value = 11),
    dispatchType -> "STATIC_DISPATCH",
    dynamicTypeHintFullName -> ArraySeq(),
    lineNumber -> Some(value = 10),
    methodFullName -> "*strLenFunc",
    name -> "*strLenFunc",
    order -> 1,
    signature -> "TODO",
    typeFullName -> "<empty>"
  )
)
```

As you can see, the old one showed a more or less correct `methodFullName` but the new one has nothing for the `methodFullName`. What I like about the new parser, is that it clearly shows the indirection which you can't see in the old one.

### Additional contract requirements

- For the call expression `(*strLenFunc)("123")`, both `name` and `methodFullName` must be `*strLenFunc`.
- Preserve the indirection in the callee `*strLenFunc` as a distinct, explicitly represented indirection operation.
