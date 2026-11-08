Is the request id unique globally?
As the document, I expect it is.
![image](https://user-images.githubusercontent.com/29651828/96822402-8a9ca300-145c-11eb-9599-950577e564ea.png)

But after I captured traffic and analyze the .gor file, I saw that request id is not seemly unique. The following picture is my traffic file and I searched one request Id but 46 matched.

![image](https://user-images.githubusercontent.com/29651828/96825782-81173900-1464-11eb-81e5-e9a22ba4ce76.png)


And I found that `tcp_message.go#UUID()` function calculates the request id by src address and dest address, which seems not to be unique.

Could you please answer this question? Thanks!

### Additional contract requirements

- `Message.UUID()` is deterministic: it returns the same identifier every time it is called for a given message, and two messages with the same sequence number and timestamp produce the same identifier.
- For requests with the same endpoints, changing the sequence number or timestamp must change the identifier; the endpoint pair alone must not determine the identifier.
