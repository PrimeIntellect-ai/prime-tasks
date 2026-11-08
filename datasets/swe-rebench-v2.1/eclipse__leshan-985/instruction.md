Leshan does not decode SenML-CBOR/JSON data value (vd/8) correctly
Hi Leshan Team

I'm trying out the AVSystem's Coiote LwM2M stack (both bootstrap and device management) using Leshan client demo.
When I connect the client to the bootstrap server, I get this error when the server sends back the device manager info to connect to:

```
2021-03-19 14:26:48,006 ERROR LwM2mCoapResource - Exception while handling request [CON-PUT    MID= 7581, Token=3EA719C0258E200B, OptionSet={"Uri-Path":"0", "Content-Format":"application/senml+cbor"},
8d a3 21 63 2f 30 2f 00 63 31 2f 30 03 78 23 63 6f 61 70 73 3a 2f 2f 6c 77 6d 32 6d 2d 74 65 73
74 2e 61 76 73 79 73 74 65 6d 2e 69 6f 3a 35 36 39 34 a2 00 63 31 2f 32 02 00 a2 00 63 31 2f 33
08 47 74 65 73 74 2d 6a 62 a2 00 63 31 2f 35 08 58 18 58 59 37 6d 73 43 46 4f 30 47 61 67 64 34
46 77 6b 56 36 6f 36 6a 6b 33 a2 00 63 31 2f 34 08 40 a2 00 63 31 2f 31 04 f5 a2 00 63 32 2f 30
03 78 23 63 6f 61 70 73 3a 2f 2f 6c 77 6d 32 6d 2d 74 65 73 74 2e 61 76 73 79 73 74 65 6d 2e 69
6f 3a 35 36 38 34 a2 00 63 32 2f 32 02 00 a2 00 63 32 2f 33 08 47 74 65 73 74 2d 6a 62 a2 00 63
32 2f 35 08 58 18 6b 72 56 63 43 62 6e 55 61 42 56 72 53 35 48 59 32 52 42 51 4e 72 52 76 a2 00
63 32 2f 34 08 40 a2 00 63 32 2f 31 04 f4 a2 00 64 32 2f 31 30 02 01 ] on the resource /0 from Identity lwm2m-test.avsystem.io/35.241.179.127:5694[psk=test-jb]
org.eclipse.leshan.core.util.json.JsonException: Invalid SenML record : record must have a value (v,vb,vlo,vd,vs) : {0: "1/3", 8: h'746573742D6A62'}
	at org.eclipse.leshan.senml.cbor.upokecenter.SenMLCborPackSerDes.deserializeFromCbor(SenMLCborPackSerDes.java:117)
	at org.eclipse.leshan.senml.cbor.upokecenter.SenMLCborUpokecenterEncoderDecoder.fromSenML(SenMLCborUpokecenterEncoderDecoder.java:72)
	at org.eclipse.leshan.core.node.codec.senml.LwM2mNodeSenMLDecoder.decode(LwM2mNodeSenMLDecoder.java:68)
	at org.eclipse.leshan.core.node.codec.DefaultLwM2mNodeDecoder.decode(DefaultLwM2mNodeDecoder.java:127)
	at org.eclipse.leshan.core.node.codec.DefaultLwM2mNodeDecoder.decode(DefaultLwM2mNodeDecoder.java:109)
	at org.eclipse.leshan.client.californium.object.ObjectResource.handlePUT(ObjectResource.java:228)
	at org.eclipse.californium.core.CoapResource.handleRequest(CoapResource.java:228)
	at org.eclipse.leshan.core.californium.LwM2mCoapResource.handleRequest(LwM2mCoapResource.java:51)
	at org.eclipse.californium.core.server.ServerMessageDeliverer.deliverRequest(ServerMessageDeliverer.java:106)
	at org.eclipse.californium.core.network.stack.BaseCoapStack$StackTopAdapter.receiveRequest(BaseCoapStack.java:204)
	at org.eclipse.californium.core.network.stack.AbstractLayer.receiveRequest(AbstractLayer.java:84)
	at org.eclipse.californium.core.network.stack.AbstractLayer.receiveRequest(AbstractLayer.java:84)
	at org.eclipse.californium.core.network.stack.BlockwiseLayer.receiveRequest(BlockwiseLayer.java:413)
	at org.eclipse.californium.core.network.stack.ReliabilityLayer.receiveRequest(ReliabilityLayer.java:275)
	at org.eclipse.californium.core.network.stack.AbstractLayer.receiveRequest(AbstractLayer.java:84)
	at org.eclipse.californium.core.network.stack.BaseCoapStack.receiveRequest(BaseCoapStack.java:137)
	at org.eclipse.californium.core.network.CoapEndpoint$1.receiveRequest(CoapEndpoint.java:309)
	at org.eclipse.californium.core.network.UdpMatcher$2.run(UdpMatcher.java:270)
	at org.eclipse.californium.elements.util.SerialExecutor$1.run(SerialExecutor.java:289)
	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
	at java.base/java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:304)
	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
	at java.base/java.lang.Thread.run(Thread.java:836)
2021-03-19 14:28:19,770 INFO DefaultRegistrationEngine - Bootstrap sequence aborted: Timeout.
```

I asked about it and the guys at AV Systems say that it's probably a bug on Leshan's side as it is expecting text labels instead of numeric ones.
I've had the same result with *master* and *demo_v2* branches and  *leshan-2.0.0-M2* tag


BR

Jacinto
