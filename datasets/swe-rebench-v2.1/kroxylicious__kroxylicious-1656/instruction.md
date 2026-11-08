Rewrite broker address information carried by ShareFetchResponse and ShareAckResponse  (KIP-932)
**Is your feature request related to a problem? Please describe.**

**Describe the solution you'd like**

[KIP-923](https://cwiki.apache.org/confluence/display/KAFKA/KIP-932%3A+Queues+for+Kafka#KIP932:QueuesforKafka-Fetchingandacknowledgingrecords) (Queues for Apache Kafka) is currently partially delivered in Kafka 3.9. It is marked as "unstable" so it is disabled by default.

KIP-932 introduces several new RPC.  Two of those RPCs `ShareFetchResponse` and `ShareAckResponse` carry node host/port information.  In order to allow users of the proxy (and Filter authors) the freedom to experiment with KIP-932, the Kroxylicious Core  needs to rewrite the broker addresses in the new RPCs.  If this is not done, the Kafka Client will fail.

`BrokerAddressFilter` needs to intercept the two new RPCs and rewrite the broker addresses contained within the response.
It should be able to to this using the established pattern.   We should add some supporting tests.


**Describe alternatives you've considered**

**Additional context**
Add any other context or screenshots about the feature request here.
