Implement `leaveChat` method
ref https://core.telegram.org/bots/api#leavechat

```php

Telegraph::chat($telegraphChat)->leaveChat()

//or

$chat->leave()
```

### Additional contract requirements

- `Telegraph::leaveChat()` (on `DefStudio\Telegraph\Telegraph`) returns a new `Telegraph` instance configured with endpoint `leaveChat` and `chat_id` set to the selected chat's id.
- `TelegraphChat::leave()` (on `DefStudio\Telegraph\Models\TelegraphChat`) returns the `Telegraph` request that leaves the chat for the model's associated bot and chat.
- Define the public constant `Telegraph::ENDPOINT_LEAVE_CHAT` with value `leaveChat`.
