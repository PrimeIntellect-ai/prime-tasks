Maintain conditional expression branch position, or a add "match" like formatting
In the TypeScript project, we often write conditional expressions like this:

```ts
function base64FormatEncode(value) {
    return value < 0 ? fail("Invalid value") :
        value < 26 ? 0x41 /*A*/ + value :
        value < 52 ? 0x61 /*a*/ + value - 26 :
        value < 62 ? 0x30 /*0*/ + value - 52 :
        value === 62 ? 0x2B /*+*/ :
        value === 63 ? 0x2F /*/*/ :
        fail("Invalid value");
}
```

or

```ts
function getApparentType(type: Type): Type {
    const t = !(type.flags & TypeFlags.Instantiable) ? type : getBaseConstraintOfType(type) || unknownType;
    return getObjectFlags(t) & ObjectFlags.Mapped ? getApparentTypeOfMappedType(t as MappedType) :
        t.flags & TypeFlags.Intersection ? getApparentTypeOfIntersectionType(t as IntersectionType) :
        t.flags & TypeFlags.StringLike ? globalStringType :
        t.flags & TypeFlags.NumberLike ? globalNumberType :
        t.flags & TypeFlags.BigIntLike ? getGlobalBigIntType() :
        t.flags & TypeFlags.BooleanLike ? globalBooleanType :
        t.flags & TypeFlags.ESSymbolLike ? getGlobalESSymbolType() :
        t.flags & TypeFlags.NonPrimitive ? emptyObjectType :
        t.flags & TypeFlags.Index ? keyofConstraintType :
        t.flags & TypeFlags.Unknown && !strictNullChecks ? emptyObjectType :
        t;
}
```

Where it's a chain of cases, condition on the left, result on the right.

When I format this with dprint, these are reformatted to split the cases apart (with the operator being positioned according to `conditionalExpression.operatorPosition`):

```ts
function base64FormatEncode(value) {
    return value < 0 ?
        fail("Invalid value") :
        value < 26 ?
        0x41 /*A*/ + value :
        value < 52 ?
        0x61 /*a*/ + value - 26 :
        value < 62 ?
        0x30 /*0*/ + value - 52 :
        value === 62 ?
        0x2B : /*+*/
        value === 63 ?
        0x2F : /*/*/
        fail("Invalid value");
}
```

```ts
function getApparentType(type: Type): Type {
    const t = !(type.flags & TypeFlags.Instantiable) ? type : getBaseConstraintOfType(type) || unknownType;
    return getObjectFlags(t) & ObjectFlags.Mapped ?
        getApparentTypeOfMappedType(t as MappedType) :
        t.flags & TypeFlags.Intersection ?
        getApparentTypeOfIntersectionType(t as IntersectionType) :
        t.flags & TypeFlags.StringLike ?
        globalStringType :
        t.flags & TypeFlags.NumberLike ?
        globalNumberType :
        t.flags & TypeFlags.BigIntLike ?
        getGlobalBigIntType() :
        t.flags & TypeFlags.BooleanLike ?
        globalBooleanType :
        t.flags & TypeFlags.ESSymbolLike ?
        getGlobalESSymbolType() :
        t.flags & TypeFlags.NonPrimitive ?
        emptyObjectType :
        t.flags & TypeFlags.Index ?
        keyofConstraintType :
        t.flags & TypeFlags.Unknown && !strictNullChecks ?
        emptyObjectType :
        t;
}
```

Is there any way that these conditional expressions could be maintained?

Adding a special mode that would explicitly format conditionals like this may also work, but I can't say that all of our examples of this are formatted like this (but a lot are, especially in the checker).

### Additional contract requirements

Provide a user-configurable `conditionalExpression.linePerExpression` option. When disabled, a multi-case conditional expression can retain the branch placement written by the programmer rather than having each conditional part forced onto a separate line. Other formatting choices for single conditional expressions and comments are not prescribed.
