TranscriptionRequest responseFormat always text
Hi, as I understand we can request  a responseFormat from TranscriptionRequest . But whether I use json, or verbose_json transcription.text is always int text format. I can see json respone in the body when I enable logging

Question is how to get json formatted version of the response?

Also, when I use  srt or vtt I get below error. I can see actual response in the log output but looks like ktor does not know how to handle it.

com.aallam.openai.api.exception.OpenAIHttpException
	at com.aallam.openai.client.internal.http.HttpTransport.perform(HttpTransport.kt:23)
	at com.aallam.openai.client.internal.http.HttpTransport$perform$1.invokeSuspend(HttpTransport.kt:0)
	at kotlin.coroutines.jvm.internal.BaseContinuationImpl.resumeWith(ContinuationImpl.kt:33)
	at kotlinx.coroutines.DispatchedTask.run(DispatchedTask.kt:106)
	at kotlinx.coroutines.EventLoopImplBase.processNextEvent(EventLoop.common.kt:284)
	at kotlinx.coroutines.BlockingCoroutine.joinBlocking(Builders.kt:85)
	at kotlinx.coroutines.BuildersKt__BuildersKt.runBlocking(Builders.kt:59)
	at kotlinx.coroutines.BuildersKt.runBlocking(Unknown Source:1)
	at kotlinx.coroutines.BuildersKt__BuildersKt.runBlocking$default(Builders.kt:38)
	at kotlinx.coroutines.BuildersKt.runBlocking$default(Unknown Source:1)
	at com.test.client.openai.conector.OpenAiWhisperConnector.upload(OpenAiWhisperConnector.kt:43)
	at com.test.client.openai.OpenAiWhisperClient.upload(OpenAiWhisperClient.kt:21)

### Additional contract requirements

- When a transcription is requested in JSON format, the returned transcription exposes the response's transcription text as its `text` value, rather than treating the complete JSON document as plain text.
- For a `verbose_json` transcription response, the returned transcription makes the response's `language`, `duration`, and `segments` available with their returned values.
- Text, SRT, and VTT transcription responses are returned as text and do not fail because they are not JSON.
