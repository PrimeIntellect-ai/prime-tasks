Robots parser to always handle absolute sitemap URL even without valid base URL
I get an `Invalid URL with sitemap directive` for a sitemap url which is not relative.

I noticed in the implementation [here](https://github.com/crawler-commons/crawler-commons/blob/master/src/main/java/crawlercommons/robots/SimpleRobotRulesParser.java#L740) that it only handles relative URLs, which might not be the case always, as now it is preferred to have the absolute URL for the sitemap in `robots.txt`.

Therefore if there is a URL provided with the sitemap, we cannot access it.
