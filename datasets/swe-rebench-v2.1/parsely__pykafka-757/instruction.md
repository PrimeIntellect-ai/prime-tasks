Support updated versions of MetadataRequest
pykafka currently only supports `MetadataRequest` and `MetadataResponse` v0. It needs to handle requests from later versions of the protocol. #750 is blocked by this.

### Additional contract requirements

Add the following public classes to the `pykafka.protocol` module:

- `MetadataRequestV1(topics=None)`, `MetadataRequestV2(topics=None)` and
  `MetadataRequestV3(topics=None)`: version 1, 2 and 3 metadata requests. When
  `topics` is omitted the request asks for all topics; when an iterable of topic
  names (`bytes`) is supplied, those topics are encoded in the request. For
  versions 1 and later, omitting `topics` encodes a null topics array (length
  `-1`).
- `MetadataRequestV4(topics=None, allow_topic_autocreation=True)` and
  `MetadataRequestV5(topics=None, allow_topic_autocreation=True)`: version 4 and
  5 metadata requests. They accept the same `topics` argument and additionally
  encode the `allow_topic_autocreation` boolean, which defaults to `True` and is
  honored when explicitly set to `False`.
- `MetadataResponseV1(buff)`, `MetadataResponseV2(buff)`,
  `MetadataResponseV3(buff)`, `MetadataResponseV4(buff)` and
  `MetadataResponseV5(buff)`: version 1 through 5 metadata responses parsed from
  a raw buffer.

Each request object serializes itself with `get_bytes()`.

Parsed responses expose:
- `brokers`: mapping of broker id to broker metadata, where each broker exposes
  `id`, `host`, `port` and `rack`.
- `controller_id`: the controller broker id.
- `cluster_id`: the cluster id (versions 2 and later).
- `throttle_time_ms`: the throttle time (versions 3 and later).
- `topics`: mapping of topic name to topic metadata, where each topic exposes
  `is_internal` and `partitions`; each partition exposes `leader`, `replicas`,
  `isr` and, for version 5, `offline_replicas`.


- Each request's serialized header must use the client ID `b'pykafka'`.

- When a broker advertises a later Metadata API version that the client supports, Metadata communication must use a compatible later request and response version rather than remaining at version 0.
