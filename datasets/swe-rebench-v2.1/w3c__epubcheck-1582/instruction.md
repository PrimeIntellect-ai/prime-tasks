Null exception on checking data URL - EpubCheck 5.0.1 and 5.1.0
Hi,

When I check a fixed layout epub using the EpubCheck 5.0.1 or EpubCheck 5.1.0, I get the following. No errors on EpubCheck 5.0.0 and earlier versions. OPF file is also validated and has no resource path issues:

java.lang.NullPointerException: null input
	at io.mola.galimatias.URLParser.parse(URLParser.java:215)
	at io.mola.galimatias.URL.withPath(URL.java:397)
	at io.mola.galimatias.canonicalize.DecodeUnreservedCanonicalizer.canonicalize(DecodeUnreservedCanonicalizer.java:41)
	at org.w3c.epubcheck.util.url.URLUtils.normalize(URLUtils.java:188)
	at com.adobe.epubcheck.ocf.OCFContainer.contains(OCFContainer.java:88)
	at com.adobe.epubcheck.ocf.OCFContainer.isRemote(OCFContainer.java:134)
	at org.w3c.epubcheck.core.references.ResourceReferencesChecker.checkReference(ResourceReferencesChecker.java:120)
	at org.w3c.epubcheck.core.references.ResourceReferencesChecker.check(ResourceReferencesChecker.java:102)
	at com.adobe.epubcheck.opf.OPFChecker.checkPackage(OPFChecker.java:149)
	at com.adobe.epubcheck.opf.OPFChecker30.checkPackage(OPFChecker30.java:67)
	at com.adobe.epubcheck.opf.OPFChecker.check(OPFChecker.java:94)
	at com.adobe.epubcheck.ocf.OCFChecker.check(OCFChecker.java:173)
	at com.adobe.epubcheck.api.EpubCheck.doValidate(EpubCheck.java:218)
	at com.adobe.epubcheck.tool.EpubChecker.validateFile(EpubChecker.java:250)
	at com.adobe.epubcheck.tool.EpubChecker.processFile(EpubChecker.java:325)
	at com.adobe.epubcheck.tool.EpubChecker.run(EpubChecker.java:150)
	at com.adobe.epubcheck.tool.Checker.main(Checker.java:31)
