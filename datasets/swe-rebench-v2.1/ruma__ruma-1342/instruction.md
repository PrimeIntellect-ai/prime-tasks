Add helper method to create replacements (edits)
We have methods to help create replies, so we should probably have one to create a replacement ([MSC2676](https://github.com/matrix-org/matrix-spec-proposals/blob/main/proposals/2676-message-editing.md)), which will be part of the spec in v1.4.

In general, it's only about providing a fallback representation in `content` and put the new content in `m.new_content`. The representation of a fallback is however not defined.

There is also a more complicated use case when it is the replacement of a reply, where we also need the reply fallback in the `content` of the event.

### Additional contract requirements

Expose the helper as `RoomMessageEventContent::make_replacement(original_message_id: OwnedEventId, replied_to_message: Option<&OriginalRoomMessageEvent>)`. It must retain the supplied message as `m.new_content` and include a fallback in `content`. When an original replied-to message is supplied, include its reply fallback in `content` as well. The particular fallback representation and formatting are not prescribed.
