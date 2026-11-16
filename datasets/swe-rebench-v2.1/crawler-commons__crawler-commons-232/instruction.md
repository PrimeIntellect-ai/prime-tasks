EffectiveTldFinder throws IllegalArgumentException on IDN domain names containing prohibited characters
EffectiveTldFinder throws an IllegalArgumentException when parsing domain names containing characters prohibited in [Internationalized Domain Names](https://en.wikipedia.org/wiki/Internationalized_domain_name) (IDNs):
```
Exception in thread "main" java.lang.IllegalArgumentException: java.text.ParseException: A prohibited code point was found in the inputp?
        at java.net.IDN.toASCIIInternal(IDN.java:274)
        at java.net.IDN.toASCII(IDN.java:122)
        at java.net.IDN.toASCII(IDN.java:151)
        at crawlercommons.domains.EffectiveTldFinder$EffectiveTLD.asciiConvert(EffectiveTldFinder.java:480)
        at crawlercommons.domains.EffectiveTldFinder$EffectiveTLD.normalizeName(EffectiveTldFinder.java:428)
        at crawlercommons.domains.EffectiveTldFinder$EffectiveTLD.<init>(EffectiveTldFinder.java:416)
        at crawlercommons.domains.EffectiveTldFinder.findEffectiveTLD(EffectiveTldFinder.java:235)
        at crawlercommons.domains.EffectiveTldFinder.getAssignedDomain(EffectiveTldFinder.java:289)
        at crawlercommons.domains.EffectiveTldFinder.main(EffectiveTldFinder.java:391)
Caused by: java.text.ParseException: A prohibited code point was found in the inputp?
        at sun.net.idn.StringPrep.prepare(StringPrep.java:450)
        at java.net.IDN.toASCIIInternal(IDN.java:272)
        ... 8 more
```

Specifically, the exception was caused by a wrong encoding conversion which caused that the domain name contained the replacement character "�" (U+FFFD) which is prohibited by [RFC3490](https://tools.ietf.org/html/rfc3490) resp. [RFC3454](https://tools.ietf.org/html/rfc3454#page-78). The exception only occurs if the prohibited character is contained in the dot-separated segment "matched" by a wildcard public suffix (e.g., `*.kawasaki.jp`).

A fix should address these two points:
1. catch the runtime exception and return null or the host name depending on the configuration (parameter `strict`). Alternatively, declare and document it to avoid that applications unexpectedly crash.
2. define the behavior of EffectiveTldFinder in case the domain or host name contains prohibited characters and there is no valid ASCII representation.

### Additional contract requirements

When an IDN label containing a prohibited character cannot be converted to ASCII, `getAssignedDomain` must not propagate an `IllegalArgumentException`. In strict mode it returns `null`; in non-strict mode it returns the original hostname when the prohibited label prevents determining a valid assigned domain (including when that label matches a wildcard public suffix). A prohibited label outside the assigned domain must not prevent returning the valid assigned domain.
