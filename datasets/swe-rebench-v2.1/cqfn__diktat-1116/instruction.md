[CLASS_SHOULD_NOT_BE_ABSTRACT] should be applied to classes that does not have parental class
```
abstract class ClassesOrObjectsGenerator(protected val uses: ClassOrObjectUses) : HelperClassGenerator() {
```

if `HelperClassGenerator` is abstract, `ClassesOrObjectsGenerator` can be also abstract
