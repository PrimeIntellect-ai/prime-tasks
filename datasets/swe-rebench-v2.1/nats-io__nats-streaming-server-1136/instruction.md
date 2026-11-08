"duplicate durable registration" error after "subscribe request timeout"
I've been testing how my stan clients, written using nats.c, behave in the face of network problems introducing high packet loss (which, unfortunately, happens on rare occasions between two of our geographically dispersed sites). During my testing I've found that on some occasions, when resubscribing after a connection failure, the subscription request will fail with "subscribe request timeout" then, after retrying, will fail with "duplicate durable registration". All subsequent resubscribe attempts will fail with that message for the duration of the connection.

The reconnect logic my stan clients use is pretty straight forward and believe matches the recommendation:
* Set the ConnectionLostHandler on the stan connection
* The ConnectionLostHandler will:
  * Destroy all subscriptions
  * Destroy the connection
  * Attempt to reestablish the connection until it succeeds
  * Attempt to resubscribe each subscription until it succeeds unless the subscription fails due to NATS_CONNECTION_CLOSED in which case we stop everything and let the ConnectionLostHandler run again.

I'm simulating an unreliable network by using Linux's [NetEm](https://man7.org/linux/man-pages/man8/tc-netem.8.html). I've configured the network interface to rate limit to 150kbit and 40% packet loss (unrealistically high but appears to be quite good at hitting many possible failure cases when running for hours/days at a time). Most of the time the re-connection logic works correctly, except, of course, for the originally stated problem.

I haven't confirmed this but it appears as if the SubscriptionRequest message gets to the server but the SubscriptionResponse message doesn't get back to the client before the ConnectionWait period elapses causing a situation where the server thinks the client has a valid subscription but the client disagrees. This traps the client in a state where the subscription request can never be fulfilled until the connection stops and starts again.

Out of curiosity I tested the same scenario with nats-replicator. It too will get trapped in a "duplicate durable registration" error loop until the connection dies again.

Setting the ConnectionWait time to something higher (I've been using 10 seconds) significantly reduces the occurrence of the problem but does not entirely eliminate it.

The only work around I've been able to find is to simply destroy the connection entirely and reconnect when this error is encountered. However, that seems like a fairly drastic solution. Is there a better workaround for this?

### Additional contract requirements

The server must offer an opt-in setting that controls how a duplicate durable subscription request is handled. With the setting disabled (the default), a subscription request for a durable name that is already registered continues to be rejected with the existing "duplicate durable" error. With the setting enabled, the server must accept the new subscription request and replace the previously registered durable subscription of the same name, so that the new subscription receives subsequent messages for the subject and the replaced subscription no longer does.

The setting is exposed as a public boolean field `ReplaceDurable` on the server options, and as the boolean configuration-file key `replace_durable`.
