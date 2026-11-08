Validate ServiceLink mapping consistency during NeTEx import
## Expected behavior
The graph builder should ignore the mapping between ServiceLinks and a JourneyPattern when the number of ServiceLinks does not match the number of intervals between stops in the JourneyPattern (nbStop-1).

## Observed behavior
When a JourneyPattern is mapped to more than (nbStop-1) service links, the graph builder fails with the following exception:
An uncaught error occurred inside OTP: java.lang.ArrayIndexOutOfBoundsException: Index 46 out of bounds for length 46
```
java.lang.RuntimeException: java.lang.ArrayIndexOutOfBoundsException: Index 46 out of bounds for length 46
	at org.opentripplanner.netex.NetexModule.buildGraph(NetexModule.java:107)
	at org.opentripplanner.graph_builder.GraphBuilder.run(GraphBuilder.java:175)
	at org.opentripplanner.standalone.OTPMain.startOTPServer(OTPMain.java:138)
	at org.opentripplanner.standalone.OTPMain.main(OTPMain.java:52)
	at org.opentripplanner.ext.interactivelauncher.InteractiveOtpMain.startOtp(InteractiveOtpMain.java:38)
	at java.base/java.lang.Thread.run(Thread.java:833)
Caused by: java.lang.ArrayIndexOutOfBoundsException: Index 46 out of bounds for length 46
	at org.opentripplanner.netex.mapping.ServiceLinkMapper.getGeometriesByJourneyPattern(ServiceLinkMapper.java:77)
	at org.opentripplanner.netex.mapping.TripPatternMapper.mapTripPattern(TripPatternMapper.java:253)
	at org.opentripplanner.netex.mapping.NetexMapper.mapTripPatterns(NetexMapper.java:455)
	at org.opentripplanner.netex.mapping.NetexMapper.mapNetexToOtp(NetexMapper.java:198)
	at org.opentripplanner.netex.NetexBundle.loadFilesThenMapToOtpTransitModel(NetexBundle.java:173)
	at org.opentripplanner.netex.NetexBundle.lambda$loadFileEntries$0(NetexBundle.java:133)
	at org.opentripplanner.netex.NetexBundle.scopeInputData(NetexBundle.java:149)
	at org.opentripplanner.netex.NetexBundle.lambda$loadFileEntries$1(NetexBundle.java:131)
	at org.opentripplanner.netex.NetexBundle.scopeInputData(NetexBundle.java:149)
	at org.opentripplanner.netex.NetexBundle.loadFileEntries(NetexBundle.java:126)
	at org.opentripplanner.netex.NetexBundle.loadBundle(NetexBundle.java:100)
	at org.opentripplanner.netex.NetexModule.buildGraph(NetexModule.java:66)
	... 5 common frames omitted
```

## Version of OTP used (exact commit hash or JAR name)
dev-2.x
