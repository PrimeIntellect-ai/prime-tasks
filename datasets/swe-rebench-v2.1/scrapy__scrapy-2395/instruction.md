Sitemap spider not robust against wrong sitemap URLs in robots.txt
[The "specs"](http://www.sitemaps.org/protocol.html#submit_robots) do say that the URL should be a "full URL":

> You can specify the location of the Sitemap using a robots.txt file. To do this, simply add the following line including the full URL to the sitemap:
> `Sitemap: http://www.example.com/sitemap.xml`

But some robots.txt use relative ones.

Example: http://www.asos.com/robots.txt

```
User-agent: *
Sitemap: /sitemap.ashx
Sitemap: http://www.asos.com/sitemap.xml
Disallow: /basket/
(...)
```

Spider:
```
from scrapy.spiders import SitemapSpider


class TestSpider(SitemapSpider):
    name = "test"
    sitemap_urls = [
        'http://www.asos.com/robots.txt',
    ]

    def parse(self, response):
        self.logger.info('parsing %r' % response.url)
```
Logs:

```
$ scrapy runspider spider.py
Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/54.0.2840.90 Safari/537.36'
2016-11-09 17:46:19 [scrapy] INFO: Scrapy 1.2.1 started (bot: scrapybot)
(...)
2016-11-09 17:46:19 [scrapy] DEBUG: Crawled (200) <GET http://www.asos.com/robots.txt> (referer: None)
2016-11-09 17:46:19 [scrapy] ERROR: Spider error processing <GET http://www.asos.com/robots.txt> (referer: None)
Traceback (most recent call last):
  File "/home/paul/.virtualenvs/scrapy12/local/lib/python2.7/site-packages/scrapy/utils/defer.py", line 102, in iter_errback
    yield next(it)
  File "/home/paul/.virtualenvs/scrapy12/local/lib/python2.7/site-packages/scrapy/spidermiddlewares/offsite.py", line 29, in process_spider_output
    for x in result:
  File "/home/paul/.virtualenvs/scrapy12/local/lib/python2.7/site-packages/scrapy/spidermiddlewares/referer.py", line 22, in <genexpr>
    return (_set_referer(r) for r in result or ())
  File "/home/paul/.virtualenvs/scrapy12/local/lib/python2.7/site-packages/scrapy/spidermiddlewares/urllength.py", line 37, in <genexpr>
    return (r for r in result or () if _filter(r))
  File "/home/paul/.virtualenvs/scrapy12/local/lib/python2.7/site-packages/scrapy/spidermiddlewares/depth.py", line 58, in <genexpr>
    return (r for r in result or () if _filter(r))
  File "/home/paul/.virtualenvs/scrapy12/local/lib/python2.7/site-packages/scrapy/spiders/sitemap.py", line 36, in _parse_sitemap
    yield Request(url, callback=self._parse_sitemap)
  File "/home/paul/.virtualenvs/scrapy12/local/lib/python2.7/site-packages/scrapy/http/request/__init__.py", line 25, in __init__
    self._set_url(url)
  File "/home/paul/.virtualenvs/scrapy12/local/lib/python2.7/site-packages/scrapy/http/request/__init__.py", line 57, in _set_url
    raise ValueError('Missing scheme in request url: %s' % self._url)
ValueError: Missing scheme in request url: /sitemap.ashx
2016-11-09 17:46:19 [scrapy] INFO: Closing spider (finished)
2016-11-09 17:46:19 [scrapy] INFO: Dumping Scrapy stats:
{'downloader/request_bytes': 291,
 'downloader/request_count': 1,
 'downloader/request_method_count/GET': 1,
 'downloader/response_bytes': 1857,
 'downloader/response_count': 1,
 'downloader/response_status_count/200': 1,
 'finish_reason': 'finished',
 'finish_time': datetime.datetime(2016, 11, 9, 16, 46, 19, 332383),
 'log_count/DEBUG': 2,
 'log_count/ERROR': 1,
 'log_count/INFO': 7,
 'response_received_count': 1,
 'scheduler/dequeued': 1,
 'scheduler/dequeued/memory': 1,
 'scheduler/enqueued': 1,
 'scheduler/enqueued/memory': 1,
 'spider_exceptions/ValueError': 1,
 'start_time': datetime.datetime(2016, 11, 9, 16, 46, 19, 71714)}
2016-11-09 17:46:19 [scrapy] INFO: Spider closed (finished)
```

### Additional contract requirements

- `sitemap_urls_from_robots(robots_text, base_url=None)` yields the sitemap URLs declared in `robots_text`. When `base_url` is provided, relative URLs are resolved against it and URL schemes are lowercase; when `base_url` is omitted or `None`, URLs are yielded unchanged.
- The `sitemap:` directive is matched case-insensitively, and its URL is taken from the text after the first colon.
- When `SitemapSpider` processes a `robots.txt` response, relative sitemap declarations are resolved against that response's URL so they become absolute URLs.
