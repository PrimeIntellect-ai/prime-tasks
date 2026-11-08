Cannot parse HGVS `NP_000095.2:p.Gly168_His169=`
When trying to parse `NP_000095.2:p.Gly168_His169=` I get:

```
Caused by: de.charite.compbio.jannovar.hgvs.parser.HGVSParsingException: org.antlr.v4.runtime.NoViableAltException
	at de.charite.compbio.jannovar.hgvs.parser.HGVSErrorStrategy.reportNoViableAlternative(HGVSErrorStrategy.java:11)
	at org.antlr.v4.runtime.DefaultErrorStrategy.reportError(DefaultErrorStrategy.java:136)
	at de.charite.compbio.jannovar.hgvs.parser.Antlr4HGVSParser.aa_change_inner(Antlr4HGVSParser.java:888)
	at de.charite.compbio.jannovar.hgvs.parser.Antlr4HGVSParser.aa_change(Antlr4HGVSParser.java:743)
	at de.charite.compbio.jannovar.hgvs.parser.Antlr4HGVSParser.aa_single_allele_single_change_var(Antlr4HGVSParser.java:372)
	at de.charite.compbio.jannovar.hgvs.parser.Antlr4HGVSParser.aa_single_allele_var(Antlr4HGVSParser.java:316)
	at de.charite.compbio.jannovar.hgvs.parser.Antlr4HGVSParser.hgvs_variant(Antlr4HGVSParser.java:201)
	at de.charite.compbio.jannovar.hgvs.parser.HGVSParser.parseHGVSString(HGVSParser.java:42)
	... 75 common frames omitted
Caused by: org.antlr.v4.runtime.NoViableAltException: null
	at org.antlr.v4.runtime.atn.ParserATNSimulator.noViableAlt(ParserATNSimulator.java:2026)
	at org.antlr.v4.runtime.atn.ParserATNSimulator.execATN(ParserATNSimulator.java:467)
	at org.antlr.v4.runtime.atn.ParserATNSimulator.adaptivePredict(ParserATNSimulator.java:393)
	at de.charite.compbio.jannovar.hgvs.parser.Antlr4HGVSParser.aa_change_inner(Antlr4HGVSParser.java:820)
	... 81 common frames omitted
```

This is with Janovar 0.34.
