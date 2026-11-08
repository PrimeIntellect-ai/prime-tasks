Publish requests erroneously sent to network stack
If the socket in the network stack is disconnected (after originally being connected), the `MqttClient::publish()` function will still publish the message even though it is not possible for the message to be transmitted (due to a disconnected socket).

This can result in odd buffer overflow behavior.

The `publish()` function should silently discard the message if the socket is no longer connected.
