oneOf schema for additionalProperties throws exceptions
If you have an `additionalProperties` schema described as per below, there is a stack trace thrown during model generation.

```
additionalProperties:
  oneOf:
     - $ref: '#/component/schema/1'
     - $ref: '#/component/schema/2'
```


```
Exception in thread "main" java.lang.IllegalStateException: Unknown OAS type: object and format: null
        at ie.zalando.fabric.model.OasType$Companion.toOasType(OasType.kt:45)
        at ie.zalando.fabric.model.PolyglotTypeInfo$Companion.from(PolyglotTypeInfo.kt:60)
        at ie.zalando.fabric.model.PolyglotTypeInfo$Companion.from(PolyglotTypeInfo.kt:77)
        at ie.zalando.fabric.model.PolyglotTypeInfo$Companion.from(PolyglotTypeInfo.kt:77)
        at ie.zalando.fabric.model.PropertyInfo$MapField.<init>(PropertyInfo.kt:206)
        at ie.zalando.fabric.model.PropertyInfo$Companion.getInLinedProperties(PropertyInfo.kt:89)
        at ie.zalando.fabric.model.PropertyInfo$Companion.topLevelProperties(PropertyInfo.kt:68)
        at ie.zalando.fabric.model.PropertyInfo$Companion.topLevelProperties(PropertyInfo.kt:59)
        at ie.zalando.fabric.model.ModelInfo.<init>(ModelInfo.kt:57)
        at ie.zalando.fabric.model.ModelInfo.<init>(ModelInfo.kt:32)
        at ie.zalando.fabric.model.ModelInfo$Companion.modelInfosFromApi$fabric_generation_station(ModelInfo.kt:109)
        at ie.zalando.fabric.model.ApiSeed.<init>(ApiSeed.kt:39)
        at ie.zalando.fabric.model.ApiSeed$Companion.create(ApiSeed.kt:24)
        at ie.zalando.fabric.cli.CodeGen.generate(CodeGen.kt:41)
        at ie.zalando.fabric.cli.CodeGen.main(CodeGen.kt:22)
```

### Additional contract requirements

Generated model source for this schema must be valid Kotlin code; its representation of additional-property values may vary as long as the generated models compile.
