Compatibility with `graphql-ws` `keepAlive`
I'm experimenting with switching from Apollo Express to Fastify and Mercurius.

I discovered something a bit weird. If I enable `keepAlive` in `graphql-ws`, it will send messages that look like `{"type": "ping"}` but it seems that something on the Mercurius side is not processing them correctly.

<img width="300" alt="Screenshot 2022-08-27 at 17 50 32" src="https://user-images.githubusercontent.com/697707/187035444-473f9634-fdc4-4376-b2cd-c332b751f4f8.png">

On the other hand, If I enable `keepAlive` in Mercurius, it sends messages like `{type: "ka"}`:
<img width="131" alt="Screenshot 2022-08-27 at 17 52 03" src="https://user-images.githubusercontent.com/697707/187035502-0d39e54a-0a4a-449d-aa03-666fcb7102f1.png">

`graphql-ws` completely crashes on these messages and breaks the subscription:
<img width="638" alt="Screenshot 2022-08-27 at 17 52 38" src="https://user-images.githubusercontent.com/697707/187035518-f65d114f-bb6c-48aa-9268-a038fa6dda93.png">

My understanding is that Mercurius uses `graphql-ws`, so what's the deal here? 🙂
