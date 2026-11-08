Copy constructor of Safelist shares state
The copy constructor of Safelist `public Safelist(Safelist copy)` [HIDDEN] This causes unexpected mutation.

An example would be:
```java
Safelist safelist1 = Safelist.none().addAttributes("foo", "bar");
Safelist safelist2 = new Safelist(safelist1);
safelist1.addAttributes("foo", "baz");

final String html = "<foo bar=\"val\" baz=\"val\" />";
System.out.println(Jsoup.clean(html, safelist1));
System.out.println(Jsoup.clean(html, safelist2));
```
The second output should not contain the `baz` attribute but does.

### Additional contract requirements

A new Safelist copied from an existing one must retain the allowed tags and attributes, enforced attribute values, protocol restrictions, and relative-link preservation setting already present at the time of copying. The copied configuration must be independent: subsequent configuration changes to the source must not change the copy.
