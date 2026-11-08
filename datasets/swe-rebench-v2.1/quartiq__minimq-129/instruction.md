Allow subscribing at `QoS::ExactlyOnce`
Currently, QoS support is only implemented for sending QoS > 0 messages, but not for receiving. We need to respond with PubAck if the server ever sends us a publish message with Qos > 0 as well

### Additional contract requirements

- A subscription may request ExactlyOnce as its maximum QoS; the requested maximum is conveyed to the server.
- For an inbound QoS 1 publication, the client sends PUBACK and delivers the publication to the application.
- For an inbound QoS 2 publication, the client completes the PUBREC/PUBREL/PUBCOMP exchange and delivers the publication to the application exactly once, including when the PUBLISH is retransmitted.
