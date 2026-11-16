Stabilize threads support
[Spec PR](https://github.com/matrix-org/matrix-spec/pull/1254)

- [ ] [MSC3856](https://github.com/matrix-org/matrix-spec-proposals/pull/3856) removes filters that were introduced in [MSC3440](https://github.com/matrix-org/matrix-spec-proposals/pull/3440).
- [ ] Switch fields to the stable prefix.
- [ ] Remove the `unstable-msc3440` feature.
- [ ] We probably should add an extra `forward_thread` argument to [`RoomMessageEventContent::make_reply_to()`](https://docs.ruma.io/ruma/events/room/message/struct.RoomMessageEventContent.html#method.make_reply_to), like the one in [`RoomMessageEventContent::reply()`](https://docs.ruma.io/ruma/events/room/message/struct.RoomMessageEventContent.html#method.reply). And since now we have to methods that allow to do the same thing, maybe we should deprecate or remove of one them.

### Additional contract requirements

- `ForwardThread` is a public enum in `ruma_common::events::room::message` with the variants `Yes` and `No`.
- `RoomMessageEventContent::make_reply_to` takes `self`, a reference to the `OriginalRoomMessageEvent` being replied to, and a `ForwardThread` value, and returns `Self`.
- When `forward_thread` is `ForwardThread::Yes` and the original message belongs to a thread, the reply belongs to the same thread (the thread relation is forwarded). When `forward_thread` is `ForwardThread::No`, the reply is a regular reply in the main conversation.

- The removed MSC3440 room-event filter fields are `io.element.relation_types` (alias `related_by_rel_types`) and `io.element.relation_senders` (alias `related_by_senders`); these names are no longer supported by room-event filters.
- Deserialization must also accept legacy thread relations using `io.element.thread` and `io.element.show_reply`.
