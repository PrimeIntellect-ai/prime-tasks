erasure of java.lang.reflect.Method in tasty definition causes MatchError
## source code
```scala
// compiled by Scala 3
package javacompat

object LazyVals:
  def getOffsetStatic(field: java.lang.reflect.Field) = 1L
```

## Test case
```scala
// SignatureSuite
testWithContext("package-ref-from-tasty") {
  val LazyVals = resolve(name"javacompat" / tname"LazyVals" / obj).asClass
  val getOffsetStatic = LazyVals.getDecl(name"getOffsetStatic").get.asTerm
  assertIsSignedName(getOffsetStatic.signedName, "getOffsetStatic", "(java.lang.reflect.Field):scala.Long")
}
```

## Error

```
java.lang.ClassCastException: tastyquery.Symbols$PackageSymbol cannot be cast to tastyquery.Symbols$TermSymbol
    at tastyquery.Types$TermRef.asThisSymbolType(Types.scala:739)
    at tastyquery.Types$TermRef.asThisSymbolType(Types.scala:738)
    at tastyquery.Types$NamedType.symbol(Types.scala:557)
    at tastyquery.Types$TermRef.computeUnderlying(Types.scala:753)
    at tastyquery.Types$TermRef.underlying(Types.scala:747)
    at tastyquery.Types$NamedType.findPrefixSym$1(Types.scala:590)
    at tastyquery.Types$NamedType.computeSymbol(Types.scala:600)
    at tastyquery.Types$NamedType.symbol(Types.scala:557)
    at tastyquery.Types$TermRef.computeUnderlying(Types.scala:753)
    at tastyquery.Types$TermRef.underlying(Types.scala:747)
    at tastyquery.Types$NamedType.findPrefixSym$1(Types.scala:590)
    at tastyquery.Types$NamedType.computeSymbol(Types.scala:600)
    at tastyquery.Types$NamedType.symbol(Types.scala:557)
    at tastyquery.Types$ErasedTypeRef$.preErase(Types.scala:119)
    at tastyquery.Types$ErasedTypeRef$.erase(Types.scala:69)
    at tastyquery.Signatures$Signature$.$anonfun$1(Signatures.scala:33)
    at scala.collection.immutable.List.map(List.scala:246)
    at tastyquery.Signatures$Signature$.rec$1(Signatures.scala:33)
    at tastyquery.Signatures$Signature$.fromMethodic(Signatures.scala:44)
    at tastyquery.Symbols$TermSymbol.signature(Symbols.scala:218)
    at tastyquery.Symbols$TermSymbol.signedName(Symbols.scala:225)
    at tastyquery.SignatureSuite.$init$$$anonfun$20(SignatureSuite.scala:216)
```
