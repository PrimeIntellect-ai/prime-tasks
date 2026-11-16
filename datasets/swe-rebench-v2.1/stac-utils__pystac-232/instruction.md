version extension link setters do not check for existing links
Looking at the review comments in #199 for the scientific extension, I got derailed by version.  The mutability of a version extension item is broken.  If you set `item0.latest = item1` or set it from `apply`, and then later set `item0.lastest = item2`, item0 will end up with two SUCCESSOR links.  I don't think that is what anyone expects.

I plan to address this after #209.

Sketch of a test:

```python
    def test_set_links_twice(self):
        latest1 = make_item(2013)
        predecessor1 = make_item(2010)
        successor 1= make_item(2012)
        self.item.ext.version.apply(self.version, deprecated, latest1, predecessor1, successor1)

        year = 2015
        latest2 = make_item(year)
        expected_href = URL_TEMPLATE % year
        self.item.ext.version.latest = latest2
        links = self.item.get_links(version.LATEST)
        self.assertEqual(1, len(links))
        self.assertEqual(expected_href, link.get_href())

        year = 2009
        predecessor2 = make_item(year)
        expected_href = URL_TEMPLATE % year
        self.item.ext.version.latest = latest2
        links = self.item.get_links(version.PREDECESSOR)
        self.assertEqual(1, len(links))
        self.assertEqual(expected_href, link.get_href())

        year = 2014
        successor2 = make_item(year)
        expected_href = URL_TEMPLATE % year
        self.item.ext.version.latest = latest2
        links = self.item.get_links(version.SUCCESSOR)
        self.assertEqual(1, len(links))
        self.assertEqual(expected_href, link.get_href())
```
