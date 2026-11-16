Implement MSC3440 (Threading)
[Official MSC3440](https://github.com/matrix-org/matrix-doc/pull/3440)
[Issue in Conduit](https://gitlab.com/famedly/conduit/-/issues/96)

Necessary for forum-like apps such as [Hummingbard](https://hummingbard.com/hummingbard/introducing-hummingbard) ([repo](https://github.com/hummingbard/hummingbard)) to work. Ruma/Conduit is looking to be the easiest and most cost-effective way to self-host a Matrix community. The most advanced reference implementation of a federated, ActivityPub-compatible forum also happens to be made in Rust: [Lemmy](https://github.com/LemmyNet/lemmy).

Personally I see the greatest potential in a more Discourse-like client implementation, primarily designed for structured discussion as seen on Users and Internals. The official Matrix server for Rust should eventually bridge seamlessly with those two forums. I’m working with the Hummingbard developer to envision a prototype for such a chat/forum hybrid application in a soon-to-be-released rewrite of Hb.

A reference implementation exists in Dendrite:
https://github.com/matrix-org/dendrite/pull/1589
https://github.com/matrix-org/dendrite/pull/1596

It’s also been demonstrated in Cerulean:
https://github.com/matrix-org/cerulean

### Additional contract requirements

- Thread relations on room-message content must retain the thread root and the in-reply-to event when content is serialized and deserialized.
- Encrypted room-event content must support the same thread relation data.
- Bundled thread summaries must be representable and retain their latest-event content, count, and current-user participation value when serialized and deserialized.
- Room-event filters must support the MSC3440 relation-type criterion using the wire field `io.element.relation_types` and the relation-sender criterion using `io.element.relation_senders`. Criteria supplied in either field must survive serialization and deserialization, and a filter containing either criterion must not be considered empty.
