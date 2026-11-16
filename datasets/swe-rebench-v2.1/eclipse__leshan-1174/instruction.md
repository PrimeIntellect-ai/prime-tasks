LwM2mNodeSenMLDecoder sometimes fails trying to convert from double to long
Hi,

We are using Leshan 2.0.0-M5.
In the log files I sometimes see that when reading currentTime resource from device object (3/0/13) decoding sometimes fails with the following exception:

08:50:47 [CoapServer(main)#27] ERROR c.n.s.d.s.s.d.ManagerImpl - Endpoint 94193A0407000000: Read request for path 3 failed with exception: {}
org.eclipse.leshan.core.request.exception.InvalidResponseException: Unable to decode response payload of request [ReadRequest [path=/3 format=null]] from client [94193A0407000000]
	at org.eclipse.leshan.server.californium.request.LwM2mResponseBuilder.decodeCoapResponse(LwM2mResponseBuilder.java:458)
	at org.eclipse.leshan.server.californium.request.LwM2mResponseBuilder.visit(LwM2mResponseBuilder.java:122)
	at org.eclipse.leshan.core.request.ReadRequest.accept(ReadRequest.java:187)
	at org.eclipse.leshan.server.californium.request.RequestSender$2.buildResponse(RequestSender.java:226)
	at org.eclipse.leshan.core.californium.AsyncRequestObserver$1.onResponse(AsyncRequestObserver.java:60)
	at org.eclipse.leshan.core.californium.CoapAsyncRequestObserver.onResponse(CoapAsyncRequestObserver.java:99)
	at org.eclipse.californium.core.coap.Request.setResponse(Request.java:931)
	at org.eclipse.californium.core.server.ServerMessageDeliverer.deliverResponse(ServerMessageDeliverer.java:258)
	at org.eclipse.californium.core.network.stack.BaseCoapStack$StackTopAdapter.receiveResponse(BaseCoapStack.java:217)
	at org.eclipse.californium.core.network.stack.AbstractLayer.receiveResponse(AbstractLayer.java:89)
	at org.eclipse.californium.core.network.stack.ExchangeCleanupLayer.receiveResponse(ExchangeCleanupLayer.java:105)
	at org.eclipse.californium.core.network.stack.ObserveLayer.receiveResponse(ObserveLayer.java:139)
	at org.eclipse.californium.core.network.stack.BlockwiseLayer.receiveResponse(BlockwiseLayer.java:776)
	at org.eclipse.californium.core.network.stack.ReliabilityLayer.receiveResponse(ReliabilityLayer.java:308)
	at org.eclipse.californium.core.network.stack.AbstractLayer.receiveResponse(AbstractLayer.java:89)
	at org.eclipse.californium.core.network.stack.BaseCoapStack.receiveResponse(BaseCoapStack.java:146)
	at org.eclipse.californium.core.network.CoapEndpoint$1.receiveResponse(CoapEndpoint.java:314)
	at org.eclipse.californium.core.network.UdpMatcher$4.run(UdpMatcher.java:457)
	at org.eclipse.californium.elements.util.SerialExecutor$1.run(SerialExecutor.java:290)
	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
	at java.base/java.lang.Thread.run(Thread.java:834)
Caused by: org.eclipse.leshan.core.node.codec.CodecException: Invalid content [1.638435E9] for type TIME for path /3/0/13
	at org.eclipse.leshan.core.node.codec.senml.LwM2mNodeSenMLDecoder.parseResourceValue(LwM2mNodeSenMLDecoder.java:504)
	at org.eclipse.leshan.core.node.codec.senml.LwM2mNodeSenMLDecoder.extractLwM2mResources(LwM2mNodeSenMLDecoder.java:426)
	at org.eclipse.leshan.core.node.codec.senml.LwM2mNodeSenMLDecoder.parseRecords(LwM2mNodeSenMLDecoder.java:193)
	at org.eclipse.leshan.core.node.codec.senml.LwM2mNodeSenMLDecoder.decode(LwM2mNodeSenMLDecoder.java:97)
	at org.eclipse.leshan.core.node.codec.DefaultLwM2mDecoder.decode(DefaultLwM2mDecoder.java:156)
	at org.eclipse.leshan.core.node.codec.DefaultLwM2mDecoder.decode(DefaultLwM2mDecoder.java:138)
	at org.eclipse.leshan.server.californium.request.LwM2mResponseBuilder.decodeCoapResponse(LwM2mResponseBuilder.java:450)
	... 21 common frames omitted
Caused by: java.lang.IllegalStateException: Can not convert 1.638435E9 to long safely : Unsupported number java.lang.Double
	at org.eclipse.leshan.core.util.datatype.NumberUtil.numberToLong(NumberUtil.java:59)
	at org.eclipse.leshan.core.node.codec.senml.LwM2mNodeSenMLDecoder.numberToLong(LwM2mNodeSenMLDecoder.java:527)
	at org.eclipse.leshan.core.node.codec.senml.LwM2mNodeSenMLDecoder.parseResourceValue(LwM2mNodeSenMLDecoder.java:493)
	... 27 common frames omitted

Best regards,
Sonny
