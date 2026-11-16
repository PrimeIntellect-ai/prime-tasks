About Error handling
Hi, when I am using Azure openai chatgpt, I refer to the example of Error handling and cannot catch the error code 429. Every time the 429 code appears, the program will run into the default code block. I am not sure whether it is a problem with my operation or The content returned by azure openai is different from that of openai.
go-openai failed to serialize error messages correctly.THANKS!

```GOLANG
func OpenaiErrorAndCode(openaierr error) (code int, err error) {
	var openaiError = &openai.APIError{}
	if errors.As(openaierr, &openaiError) {
		switch openaiError.HTTPStatusCode {
		case 400:
			return 400, errors.New("xxxxxxx")
		case 401:
			return 401, errors.New("xxxxxxx")
		case 429:
			return 429, errors.New("xxxxxxx")
		case 500:
			return 500, errors.New("xxxxxxx")
		default:
				return 500, errors.New("unknown：" + openaierr.Error())
		}
	}
	return 500, openaierr
}
```
```GOLANG
stream, err := client.CreateChatCompletionStream(ctx, req)
if err != nil {
	fmt.Printf("ChatCompletionStream error: %v\n", err)
	_,openaierr := appError.OpenaiErrorAndCode(err)
	fmt.Printf(openaierr.Error())
}
```

The json returned by azure openai is as follows：
```json
{
    "error": {
        "code": "429",
        "message": "Requests to the Creates a completion for the chat message Operation under Azure OpenAI API version 2023-03-15-preview have exceeded token rate limit of your current OpenAI S0 pricing tier. Please retry after 20 seconds. Please go here: https://aka.ms/oai/quotaincrease if you would like to further increase the default rate limit."
    }
}
```
