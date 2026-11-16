Corrupted messages when websocket consumer is active
### Observed behavior

I've observed both reordering of the bytes within the message, as well as extra bytes being added (e.g. `PONG`  added at a random point within the message). This is not consistent for the same message - if a message is published to jetstream and then repeatedly requested, corruption may only occur some of the time and the corrupted message may be different each time (even though no new publishes have happened).

This only happens when a websocket client is connected and receiving messages, but messages sent to other clients (e.g. nats-cli) during this time may also be corrupted. Other clients return to normal ~30s after the websocket client is closed.

Only occurs for fairly specific message sizes - I can reliably reproduce with ~790000 bytes.

### Expected behavior

Messages always arrive intact.

### Server and client version

nats-server 2.10.5, still occurs on `main`

Bisected to 6b65452bc70973d9bcf59857afa94ae46b04bdf4

Clients:
nats-cli 0.1.1
nats.ws 1.19.1

### Host environment

Arch Linux x86_64

Have reproduced on multiple machines with different specs.

### Steps to reproduce

<details>
<summary>
Server config
</summary>

```
listen: localhost:4222
max_payload: 8MB

http: localhost:8222

jetstream {
    store_dir: store
}

websocket {
    listen: localhost:8443
    no_tls: true
}
```
</details>

<details>
<summary>
Stream config
</summary>

```
{
    "name": "test",
    "subjects": [
      "test"
    ],
    "retention": "limits",
    "max_consumers": -1,
    "max_msgs_per_subject": -1,
    "max_msgs": -1,
    "max_bytes": -1,
    "max_age": 604800000000000,
    "max_msg_size": -1,
    "storage": "file",
    "discard": "old",
    "num_replicas": 1,
    "duplicate_window": 120000000000,
    "sealed": false,
    "deny_delete": false,
    "deny_purge": false,
    "allow_rollup_hdrs": false,
    "allow_direct": false,
    "mirror_direct": false
}
```
</details>

<details>
<summary>
Websocket client:
</summary>

```
<!DOCTYPE html>
<script type="module">
import { connect, DeliverPolicy } from "https://unpkg.com/nats.ws@1.19.1/esm/nats.js";
const nats = await connect({
    servers: "ws://localhost:8443",
    waitOnFirstConnect: true,
    // no limit
    maxReconnectAttempts: -1,
});

for (;;) {
    const consumer = await nats
        .jetstream()
        .consumers.get("test", {
            filterSubjects: "test",
            deliver_policy: DeliverPolicy.Last,
        });
    for await (const msg of await consumer.consume()) {
        console.log("received");
    }
}
</script>
```
</details>

Steps
```
# generate 79000 random bytes
cat /dev/urandom | base64 | head -c 790000 > rand.dat

# publish to jetstream
nats publish test < rand.dat

# keep trying to read the message until it is corrupted
while nats subscribe --raw --count 1 --last-per-subject test | diff -qw - rand.dat ; do :; done

# open websocket client, observe that above loop stops as message is corrupted
```
