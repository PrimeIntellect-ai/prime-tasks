chatMember method not exist
get error when call chatMember method :
When I try this:
```
$chat =  TelegraphChat::where('chat_id', '-1001917277777')->first();
$chat->chatMember('367389764')->send();
```
I get this error:

`local.ERROR: Call to undefined method DefStudio\Telegraph\Models\TelegraphChat::chatMember() `

### Additional contract requirements

- `DefStudio\Telegraph\Models\TelegraphChat::memberInfo(string $userId)` retrieves information about a specific chat member from Telegram and returns a `DefStudio\Telegraph\DTO\ChatMember` instance when the member exists.
- `DefStudio\Telegraph\Telegraph::chat()` exposes a `chatMember(string $userId)` method that returns a chat-member request builder which can be sent with `->send()`.
