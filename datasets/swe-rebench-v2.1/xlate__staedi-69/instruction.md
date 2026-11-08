EDIFACT release element throws exception from writer with UNA
EDIFACT release element throws exception from writer when using the `UNA` segment.

```
java.lang.StringIndexOutOfBoundsException: String index out of range: 20
	at java.lang.AbstractStringBuilder.charAt(AbstractStringBuilder.java:237)
	at java.lang.StringBuilder.charAt(StringBuilder.java:76)
	at io.xlate.edi.internal.stream.tokenization.EDIFACTDialect.parseVersion(EDIFACTDialect.java:97)
	at io.xlate.edi.internal.stream.tokenization.EDIFACTDialect.initialize(EDIFACTDialect.java:66)
	at io.xlate.edi.internal.stream.tokenization.EDIFACTDialect.processServiceStringAdvice(EDIFACTDialect.java:224)
	at io.xlate.edi.internal.stream.tokenization.EDIFACTDialect.appendHeader(EDIFACTDialect.java:172)
	at io.xlate.edi.internal.stream.StaEDIStreamWriter.write(StaEDIStreamWriter.java:314)
...
```

### Additional contract requirements

- When an interchange is written with an empty `UNA` segment followed by `UNB+UNOA:4:::2+005435656:1+006415160:1+060515:1434+00000000000778`, the serialized output must be exactly `UNA:+.?*'UNB+UNOA:4:::2+005435656:1+006415160:1+060515:1434+00000000000778'`.
