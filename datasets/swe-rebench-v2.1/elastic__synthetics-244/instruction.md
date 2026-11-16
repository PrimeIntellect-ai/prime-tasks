Record `dataLength` from Chrome Dev Tools Protocol
Currently, we record `encodedDataLength` from Chrome Dev Tools Protocol, but not `dataLength`. It would be helpful to have both values to display to the end user as part of the waterfall chart flyout.

Associated ticket: https://github.com/elastic/kibana/issues/80166

Reference: https://chromedevtools.github.io/devtools-protocol/tot/Network/#event-dataReceived
