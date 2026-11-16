FR: selectFirst() and expectFirst() on org.jsoup.select.Elements
It'd be useful to be able to use `selectFirst()` and `expectFirst()` on `org.jsoup.select.Elements` instances to mirror the methods in `org.jsoup.nodes.Element`.
As far as I understand this is because `org.jsoup.select.Selector` provides both `select(String, Element)` and `select(String, Iterable<Element>)` but only `selectFirst(String, Element)`.

I could take a look at it myself, but people knowledgeable about jsoup internals would probably take much less time.

Bonus points if it's actually faster than `select(...).first()` 😉

Thanks for your work
