How to change request timeout for createChatCompletion
I am using the chat completion function like so: `val response: ChatResponse = openAI.createChatCompletion(chatRequestBody)`

When I run it against the current top model, 'p1-preview', I run into 30 second timeouts. '01-preview' is designed to take longer to reason, so it is ok if it takes longer.

The timeout I get: `java.util.concurrent.TimeoutException: test timed out after 30 seconds`

I did not find a parameter on 'createChatCompletion' to increase the timeout. How to do it?

edit: By using a DefaultSyncBackend I can adjust the connection timeout: `val backend = DefaultSyncBackend(BackendOptions.connectionTimeout(5.minutes))`

But that does not help in my case, because I need a larger request timeout.

### Additional contract requirements

- Add a public method `customizeRequest(customize: CustomizeOpenAIRequest): OpenAISyncClient` on `OpenAISyncClient`. It returns a new `OpenAISyncClient` that applies the supplied customizer to every outgoing request, including chat completion requests. Registering another customizer composes it with the previously registered ones, so that every registered customizer is applied to each outgoing request.
- Add a public trait `CustomizeOpenAIRequest` with a method `apply[A](request: sttp.client4.Request[Either[OpenAIException, A]]): sttp.client4.Request[Either[OpenAIException, A]]` that transforms an outgoing request, for example to set a longer request timeout.
