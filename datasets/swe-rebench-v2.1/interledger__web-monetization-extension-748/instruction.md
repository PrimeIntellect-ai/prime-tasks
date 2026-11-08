Don't cache rejected promises in deduplicator service
### Context

By default we do not want the `deduplicator`  service to cache rejected promises
See https://github.com/interledger/web-monetization-extension/pull/714#discussion_r1863281698

### Todos

- [ ] Deduplicator unit test coverage
