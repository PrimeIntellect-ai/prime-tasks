Nested packages can't be found from their parent packages
`lang` cannot be found as a member of `java`. Test case:
```scala
    println(resolve(name"java" / name"lang" / tname"String")) // OK: symbol[class String]
    val javaPackage = resolve(name"java".singleton).asInstanceOf[PackageClassSymbol]
    println(javaPackage) // OK: symbol[package java]
    println(javaPackage.getDecl(name"lang")) // Not OK: None
    println(TypeRef(TermRef(PackageRef(javaPackage), name"lang"), tname"String").symbol) // Not OK: throws
```

### Additional contract requirements

A type reference whose prefix selects a nested package from its parent package reference resolves to the class declared in that nested package.
