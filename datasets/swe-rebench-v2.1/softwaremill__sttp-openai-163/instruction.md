createModeration throws  "Could not deserialize: text-moderation-007"
Not sure if it throws for everyone but it does for me:

```scala
//> using dep com.softwaremill.sttp.openai::core:0.0.10
import sttp.openai.OpenAISyncClient
import sttp.openai.requests.moderations.ModerationsRequestBody.ModerationsBody

val client = OpenAISyncClient("open-ai-authToken")
client.createModeration(ModerationsBody("some text"))
```

```
$ scala-cli ./moderation.sc
Starting compilation server
Compiling project (Scala 3.4.0, JVM (21))
Compiled project (Scala 3.4.0, JVM (21))
Exception in thread "main" sttp.openai.OpenAIExceptions$OpenAIException$DeserializationOpenAIException: Could not deserialize: text-moderation-007
        at sttp.openai.OpenAIExceptions$OpenAIException$DeserializationOpenAIException$.apply(OpenAIExceptions.scala:22)
        at sttp.openai.OpenAIExceptions$OpenAIException$DeserializationOpenAIException$.apply(OpenAIExceptions.scala:24)
        at sttp.openai.json.SttpUpickleApiExtension$.deserializeJsonSnake$$anonfun$1(SttpUpickleApiExtension.scala:38)
        at sttp.openai.json.SttpUpickleApiExtension$.deserializeRightWithMappedExceptions$$anonfun$1(SttpUpickleApiExtension.scala:31)
        at sttp.client4.MappedResponseAs.mapWithMetadata$$anonfun$1(ResponseAs.scala:335)
        at sttp.client4.internal.BodyFromResponseAs.doApply$$anonfun$2$$anonfun$1$$anonfun$1(BodyFromResponseAs.scala:24)
        at sttp.client4.monad.IdMonad$.eval(IdMonad.scala:16)
        at sttp.client4.internal.BodyFromResponseAs.doApply$$anonfun$2$$anonfun$1(BodyFromResponseAs.scala:24)
        at sttp.monad.syntax$MonadErrorOps.map(MonadError.scala:60)
        at sttp.client4.internal.BodyFromResponseAs.doApply$$anonfun$2(BodyFromResponseAs.scala:24)
        at sttp.client4.monad.IdMonad$.flatMap(IdMonad.scala:9)
        at sttp.monad.syntax$MonadErrorOps.flatMap(MonadError.scala:61)
        at sttp.client4.internal.BodyFromResponseAs.doApply(BodyFromResponseAs.scala:25)
        at sttp.client4.internal.BodyFromResponseAs.apply$$anonfun$1(BodyFromResponseAs.scala:14)
        at sttp.monad.syntax$MonadErrorOps.map(MonadError.scala:60)
        at sttp.client4.internal.BodyFromResponseAs.apply(BodyFromResponseAs.scala:14)
        at sttp.client4.internal.httpclient.BodyFromHttpClient.apply(BodyFromHttpClient.scala:20)
        at sttp.client4.internal.httpclient.BodyFromHttpClient.apply$(BodyFromHttpClient.scala:11)
        at sttp.client4.httpclient.HttpClientSyncBackend$$anon$2.apply(HttpClientSyncBackend.scala:93)
        at sttp.client4.httpclient.HttpClientBackend.readResponse(HttpClientBackend.scala:126)
        at sttp.client4.httpclient.HttpClientSyncBackend.sendRegular(HttpClientSyncBackend.scala:41)
        at sttp.client4.httpclient.HttpClientSyncBackend.sendRegular(HttpClientSyncBackend.scala:38)
        at sttp.client4.httpclient.HttpClientBackend.send$$anonfun$1(HttpClientBackend.scala:46)
        at scala.util.Try$.apply(Try.scala:210)
        at sttp.monad.MonadError.handleError(MonadError.scala:24)
        at sttp.monad.MonadError.handleError$(MonadError.scala:16)
        at sttp.client4.monad.IdMonad$.handleError(IdMonad.scala:6)
        at sttp.client4.SttpClientException$.adjustExceptions(SttpClientException.scala:35)
        at sttp.client4.httpclient.HttpClientBackend.adjustExceptions(HttpClientBackend.scala:55)
        at sttp.client4.httpclient.HttpClientBackend.send(HttpClientBackend.scala:47)
        at sttp.client4.wrappers.FollowRedirectsBackend.sendWithCounter(FollowRedirectsBackend.scala:19)
        at sttp.client4.wrappers.FollowRedirectsBackend.send(FollowRedirectsBackend.scala:15)
        at sttp.client4.Request.send(request.scala:158)
        at sttp.openai.OpenAISyncClient.sendOrThrow(OpenAISyncClient.scala:791)
        at sttp.openai.OpenAISyncClient.createModeration(OpenAISyncClient.scala:331)
        at moderation$_.<init>(moderation.sc:10)
        at moderation_sc$.script$lzyINIT1(moderation.sc:25)
        at moderation_sc$.script(moderation.sc:25)
        at moderation_sc$.main(moderation.sc:29)
        at moderation_sc.main(moderation.sc)
Caused by: sttp.client4.DeserializationException: Could not deserialize: text-moderation-007
        at sttp.client4.DeserializationException$.apply(ResponseException.scala:10)
        ... 39 more
```
