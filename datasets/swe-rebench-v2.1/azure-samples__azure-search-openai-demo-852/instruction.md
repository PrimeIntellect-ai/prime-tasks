few shot reversed in get_messages_from_history
<!--
IF SUFFICIENT INFORMATION IS NOT PROVIDED VIA THE FOLLOWING TEMPLATE THE ISSUE MIGHT BE CLOSED WITHOUT FURTHER CONSIDERATION OR INVESTIGATION
-->
> Please provide us with the following information:
> ---------------------------------------------------------------

### This issue is for a: (mark with an `x`)
```
- [x] bug report -> please search issues before submitting
- [ ] feature request
- [ ] documentation issue or request
- [ ] regression (a behavior that used to work and stopped in a new release)
```

### Minimal steps to reproduce
> I noticed that the few shot messages are inserted in reverse order within the conversation, is this a desired behaviour? By not specifying the index in the append_message function, they are all inserted in the first position, reversing the list.


### Expected/desired behavior
> [HIDDEN]


> ---------------------------------------------------------------
> Thanks! We'll be in touch soon.

### Additional contract requirements

- `MessageBuilder` in module `core.messagebuilder` provides a public method `insert_message(role: str, content: str, index: int = 1)`. It inserts a message with the given `role` and `content` into the conversation at position `index`, normalizing `content` to Unicode NFC. Index 1 inserts the message immediately after the initial system message; a larger index inserts it further down the conversation. The method returns no value.
- `ChatReadRetrieveReadApproach.get_messages_from_history(system_prompt: str, model_id: str, history: list[dict], user_content: str, max_tokens: int, few_shots: list[dict])` returns a list of message dicts ordered as: the system prompt, the few-shot messages in their original order, the retained history, and finally the current user message.
