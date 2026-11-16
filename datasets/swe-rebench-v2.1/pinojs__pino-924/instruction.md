Merge error flows instead of doing a special serialisation handling
I see you are planning to fix the error serialisation in #896 in the upcoming v7.

I submitted a bug a while ago #889 which addressed the loosing of the `message` property when a `msg` is present. Your recommendation was to use `{ err }`. I asked a question there but never got an answer.

I see in #896 you are detecting the error and running the serialiser manually. Why not just [HIDDEN]?

This will have the following advantages:
* less edge case programming
* `message` property is not lost
* logs with errors will be easily detected (especially in stuff like Elasticsearch)

### Additional contract requirements

- When an `Error` is supplied as the logged object, its serialized representation must appear under an `err` field rather than as top-level error properties.
- A directly logged `Error` must be processed by the configured `err` serializer in the same way as an `Error` supplied in an `err` field. Do not lose the error's `message` merely because the log also has a message.
