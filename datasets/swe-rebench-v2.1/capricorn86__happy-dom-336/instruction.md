Serializer escapes attributes too much
I tried using happy-dom with Vitest and when switching from jsdom I got a failing test:

![image](https://user-images.githubusercontent.com/2339406/150375626-9222cbc2-cfe2-47d1-b9b4-b0c976630346.png)

![image](https://user-images.githubusercontent.com/2339406/150375278-4d61320c-caf7-4464-96af-771a173cc134.png)

happy-dom is escaping characters in html attributes that are allowed. [HIDDEN]

### Additional contract requirements

- When serializing HTML attribute values, preserve Unicode characters that are allowed as literal attribute content rather than escaping them.
- Continue escaping characters that require escaping in attribute values.
