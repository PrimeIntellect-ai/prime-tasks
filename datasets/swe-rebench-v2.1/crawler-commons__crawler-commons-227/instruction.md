[Sitemaps] Sitemap index: stop URL at closing </loc>
(cf. [Nutch mailing list](https://lists.apache.org/thread.html/8ebcffbe2bd8edafb6030e4f28fceee07aee08a1ce06a94755ee8d74@%3Cuser.nutch.apache.org%3E)

With #153 the sitemaps SAX parser handles sitemaps with missing or not properly closed <url> elements. This should be also done for sitemap indexes, e.g.:
```
<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex>
<sitemap>
<loc>https://www.example.orgl/sitemap1.xml</loc>
<loc>https://www.example.org/sitemap2.xml</loc>
</sitemap>
</sitemapindex>
```
