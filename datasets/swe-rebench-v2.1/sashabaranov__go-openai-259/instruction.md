Bug:  The `CreateChatCompletionStream` do not  return ` Rate limit ` and  ` Quota exceed `  error correctly.
The `CreateChatCompletionStream` do not return ` Rate limit` and `Quota exceed` error correctly, which is important for user to retry their requests.
```
stream, err := client.CreateChatCompletionStream(
		context.Background(),
		openai.ChatCompletionRequest{
			Model:    model,
			Messages: messages,
			Stream:   true,
		},
	)
```

I always get the `err` with `nil` value when actually meet a ` Rate limit` and `Quota exceed` issue, ` client.CreateChatCompletion` works well.
