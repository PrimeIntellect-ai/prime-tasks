RDFXML: can't parse rdf:XMLLiteral when round-trip
### Version

5.1.0

### What happened?

Probably this is duplicate of #2473
Jena produces RDF/XML, which Jena cannot read itself.

```java
String literal =
        "<ncicp:ComplexDefinition>" +
        "<ncicp:def-definition>XXX" +
        "</ncicp:def-definition>" +
        "<ncicp:def-source>NCI-GLOSS</ncicp:def-source></ncicp:ComplexDefinition>";
var m = ModelFactory.createOntologyModel();
m.createResource().addProperty(RDFS.comment, m.createTypedLiteral(literal, RDF.dtXMLLiteral));
StringWriter sw = new StringWriter();
m.write(sw, "rdf/xml");
System.out.println(sw);
StringReader sr = new StringReader(sw.toString());
ModelFactory.createDefaultModel().read(sr, null, "rdf/xml").write(System.out, "ttl");
```

### Relevant output and stacktrace

```shell
Exception in thread "main" org.apache.jena.riot.RiotException: [line: 7, col: 68] The prefix "ncicp" for element "ncicp:ComplexDefinition" is not bound.
	at org.apache.jena.riot.system.ErrorHandlerFactory$ErrorHandlerStd.fatal(ErrorHandlerFactory.java:155)
	at org.apache.jena.riot.lang.rdfxml.rrx.ParserRDFXML_SAX.fatalError(ParserRDFXML_SAX.java:1727)
	at java.xml/com.sun.org.apache.xerces.internal.util.ErrorHandlerWrapper.fatalError(ErrorHandlerWrapper.java:181)
	at java.xml/com.sun.org.apache.xerces.internal.impl.XMLErrorReporter.reportError(XMLErrorReporter.java:400)
	at java.xml/com.sun.org.apache.xerces.internal.impl.XMLErrorReporter.reportError(XMLErrorReporter.java:327)
	at java.xml/com.sun.org.apache.xerces.internal.impl.XMLErrorReporter.reportError(XMLErrorReporter.java:284)
	at java.xml/com.sun.org.apache.xerces.internal.impl.XMLNSDocumentScannerImpl.scanStartElement(XMLNSDocumentScannerImpl.java:284)
	at java.xml/com.sun.org.apache.xerces.internal.impl.XMLDocumentFragmentScannerImpl$FragmentContentDriver.next(XMLDocumentFragmentScannerImpl.java:2726)
	at java.xml/com.sun.org.apache.xerces.internal.impl.XMLDocumentScannerImpl.next(XMLDocumentScannerImpl.java:605)
	at java.xml/com.sun.org.apache.xerces.internal.impl.XMLNSDocumentScannerImpl.next(XMLNSDocumentScannerImpl.java:112)
	at java.xml/com.sun.org.apache.xerces.internal.impl.XMLDocumentFragmentScannerImpl.scanDocument(XMLDocumentFragmentScannerImpl.java:542)
	at java.xml/com.sun.org.apache.xerces.internal.parsers.XML11Configuration.parse(XML11Configuration.java:889)
	at java.xml/com.sun.org.apache.xerces.internal.parsers.XML11Configuration.parse(XML11Configuration.java:825)
	at java.xml/com.sun.org.apache.xerces.internal.parsers.XMLParser.parse(XMLParser.java:141)
	at java.xml/com.sun.org.apache.xerces.internal.parsers.AbstractSAXParser.parse(AbstractSAXParser.java:1224)
	at java.xml/com.sun.org.apache.xerces.internal.jaxp.SAXParserImpl$JAXPSAXParser.parse(SAXParserImpl.java:637)
	at org.apache.jena.riot.lang.rdfxml.rrx.ReaderRDFXML_SAX.parse(ReaderRDFXML_SAX.java:83)
	at org.apache.jena.riot.lang.rdfxml.rrx.ReaderRDFXML_SAX.read(ReaderRDFXML_SAX.java:65)
	at org.apache.jena.riot.RDFParser.read(RDFParser.java:456)
	at org.apache.jena.riot.RDFParser.parseNotUri(RDFParser.java:442)
	at org.apache.jena.riot.RDFParser.parse(RDFParser.java:379)
	at org.apache.jena.riot.RDFParserBuilder.parse(RDFParserBuilder.java:547)
	at org.apache.jena.riot.adapters.RDFReaderRIOT.read(RDFReaderRIOT.java:72)
	at org.apache.jena.rdf.model.impl.ModelCom.read(ModelCom.java:205)
```


### Are you interested in making a pull request?

None

### Additional contract requirements

- For a well-formed, self-contained XML literal, RDF/XML output must contain `rdf:parseType="Literal"` and must not contain `rdf:datatype=`. For an invalid XML literal, it must contain `rdf:datatype=` and must not contain `rdf:parseType="Literal"`.
