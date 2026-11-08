@All in the mention property of the webhooks
News URL
[Messaging API now includes @All in the mention property of the webhooks](https://developers.line.biz/en/news/2023/03/08/messaging-api-updated/)

see the [Text](https://developers.line.biz/en/reference/messaging-api/#wh-text) section of [Message event](https://developers.line.biz/en/reference/messaging-api/#message-event)

### Additional contract requirements

- The `linebot` package exposes a public string type `MentionedTargetType` that classifies the target of a mention.
- The `linebot` package exposes the constant `MentionedTargetTypeUser` with value `"user"` and the constant `MentionedTargetTypeAll` with value `"all"`.
- A mentionee carries a target type in addition to its index and length: the `Mentionee` struct exposes an `Index` (int), a `Length` (int) and a `Type` (`MentionedTargetType`) field, plus an optional `UserID` (string). The target type is read from and written to the JSON field `type`.
