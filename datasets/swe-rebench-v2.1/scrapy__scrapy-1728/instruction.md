deprecate Spider.make_requests_from_url
Hey,

`Spider.make_requests_from_url` is a shortcut for a single use case: sending initial requests from a spider with start_urls attribute. It saves a single line of code (`for url in start_urls`) in one specific use case, but yet we have to document it, users have to read about it and understand what it is for.

The name suggests it is more general - but we can't yield Link objects and get requests created by `make_requests_from_url`, it does nothing for CrawlSpider (I'd expect URLs to be passed through this method), and it is ignored for SitemapSpider. This is inconsistent.

What about deprecating `make_requests_from_url` and removing it from docs? IMHO it will make API simpler, this hook does nothing useful now, and if we ever want a general 'process URL and get a Request' method we'd have to use another name for backwards compatibility anyways.

### Additional contract requirements

- Deprecating `Spider.make_requests_from_url` means that when a spider subclass overrides `make_requests_from_url`, calling `start_requests()` emits a warning (of any category) and still yields the requests produced by the overridden method.
- A spider that does not override `make_requests_from_url` emits no such warning when `start_requests()` is called.
- `make_requests_from_url` must be removed from the documentation (it is currently documented in `docs/topics/spiders.rst`).
