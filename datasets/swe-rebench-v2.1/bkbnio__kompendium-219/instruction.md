Top level unstructured data is not supported
**Describe the bug**
When trying to document an Endpoint that responds a plain `JsonElement`, I'm no longer to start my application. It crashes with this exception:
```
[main] INFO ktor.application - Autoreload is disabled because the development mode is off.
Exception in thread "main" java.lang.IllegalStateException: Unable to parse field type from val kotlinx.serialization.json.JsonPrimitive.content: kotlin.String
	at io.bkbn.kompendium.core.handler.ObjectHandler.handleDefault(ObjectHandler.kt:88)
	at io.bkbn.kompendium.core.handler.ObjectHandler.generateFieldMap(ObjectHandler.kt:70)
	at io.bkbn.kompendium.core.handler.ObjectHandler.handle(ObjectHandler.kt:50)
	at io.bkbn.kompendium.core.Kontent$generateKTypeKontent$2.invoke(Kontent.kt:96)
	at io.bkbn.kompendium.core.util.Helpers.logged(Helpers.kt:26)
	at io.bkbn.kompendium.core.Kontent.generateKTypeKontent(Kontent.kt:78)
	at io.bkbn.kompendium.core.Kontent.generateKontent(Kontent.kt:55)
	at io.bkbn.kompendium.core.KompendiumPreFlight.addToCache(KompendiumPreFlight.kt:38)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt$mainModule$3$5.invoke(BasicPlayground.kt:225)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt$mainModule$3$5.invoke(BasicPlayground.kt:106)
	at io.ktor.routing.RoutingBuilderKt.route(RoutingBuilder.kt:18)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt$mainModule$3.invoke(BasicPlayground.kt:106)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt$mainModule$3.invoke(BasicPlayground.kt:76)
	at io.ktor.routing.RoutingKt.routing(Routing.kt:129)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt.mainModule(BasicPlayground.kt:76)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt.access$mainModule(BasicPlayground.kt:1)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt$main$1.invoke(BasicPlayground.kt:57)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt$main$1.invoke(BasicPlayground.kt:57)
	at io.ktor.server.engine.ApplicationEngineEnvironmentReloading$instantiateAndConfigureApplication$1.invoke(ApplicationEngineEnvironmentReloading.kt:321)
	at io.ktor.server.engine.ApplicationEngineEnvironmentReloading$instantiateAndConfigureApplication$1.invoke(ApplicationEngineEnvironmentReloading.kt:310)
	at io.ktor.server.engine.ApplicationEngineEnvironmentReloading.avoidingDoubleStartup(ApplicationEngineEnvironmentReloading.kt:338)
	at io.ktor.server.engine.ApplicationEngineEnvironmentReloading.instantiateAndConfigureApplication(ApplicationEngineEnvironmentReloading.kt:310)
	at io.ktor.server.engine.ApplicationEngineEnvironmentReloading.createApplication(ApplicationEngineEnvironmentReloading.kt:143)
	at io.ktor.server.engine.ApplicationEngineEnvironmentReloading.start(ApplicationEngineEnvironmentReloading.kt:277)
	at io.ktor.server.netty.NettyApplicationEngine.start(NettyApplicationEngine.kt:174)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt.main(BasicPlayground.kt:58)
	at io.bkbn.kompendium.playground.BasicPlaygroundKt.main(BasicPlayground.kt)
```

**To Reproduce**
See: https://github.com/MarcelBochtler/kompendium/commit/045e40af73425d599ec37b4d50a20f6cb1ab8c67

**Expected behavior**
The application is able to start and displays the serialized JsonElement in the OpenApi docs.

### Additional contract requirements

Top-level unstructured data is declared by annotating a user-defined type with the `@FreeFormObject`
annotation (`io.bkbn.kompendium.annotations.FreeFormObject`). The annotation must be applicable to
classes as well as to properties.

An endpoint whose response type is a user-defined type annotated with `@FreeFormObject` must start
successfully, and the generated OpenAPI specification must render that response as a free-form object
schema with `"type": "object"` and `"additionalProperties": true`. The response schema is the
free-form object itself; it is not a `$ref` to a component schema, and no component schema is
generated for the annotated type.

A property annotated with `@FreeFormObject` continues to render as a free-form field with the same
`"type": "object"` / `"additionalProperties": true` shape.
