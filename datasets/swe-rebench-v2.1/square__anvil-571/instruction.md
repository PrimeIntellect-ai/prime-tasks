compiler-utils Annotation toAnnotationSpec error
Anvil: 2.4.0-M2

While writing a custom `CodeGenerator` for anvil I've encountered a bug in `compiler-utils` module.

```kotlin
@IntKey(Int.MAX_VALUE)
class A
```

When calling `com.squareup.anvil.compiler.internal.reference.AnnotationReference#toAnnotationSpec` on this AnnotationReference I get an error:
```
Couldn't resolve FqName Int.MAX_VALUE for Psi element: Int.MAX_VALUE

        at com.squareup.anvil.compiler.internal.PsiUtilsKt.requireFqName(PsiUtils.kt:266)
        at com.squareup.anvil.compiler.internal.reference.AnnotationArgumentReference$Psi$value$2.invoke$parsePsiElement(AnnotationArgumentReference.kt:231)
        at com.squareup.anvil.compiler.internal.reference.AnnotationArgumentReference$Psi$value$2.invoke(AnnotationArgumentReference.kt:236)
        at kotlin.UnsafeLazyImpl.getValue(Lazy.kt:81)
        at com.squareup.anvil.compiler.internal.reference.AnnotationArgumentReference$Psi.getValue(AnnotationArgumentReference.kt:121)
        at com.squareup.anvil.compiler.internal.reference.AnnotationArgumentReference.value(AnnotationArgumentReference.kt:58)
        at com.squareup.anvil.compiler.internal.reference.AnnotationReference.toAnnotationSpec(AnnotationReference.kt:88)

```
