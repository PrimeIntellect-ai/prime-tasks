Results of errbacks for downloader errors are discarded
<!--

Thanks for taking an interest in Scrapy!

If you have a question that starts with "How to...", please see the Scrapy Community page: https://scrapy.org/community/.
The GitHub issue tracker's purpose is to deal with bug reports and feature requests for the project itself.

Keep in mind that by filing an issue, you are expected to comply with Scrapy's Code of Conduct, including treating everyone with respect: https://github.com/scrapy/scrapy/blob/master/CODE_OF_CONDUCT.md

The following is a suggested template to structure your issue, you can find more guidelines at https://doc.scrapy.org/en/latest/contributing.html#reporting-bugs

-->

### Description

In Scrapy 2.13, errback functions defined as generator functions are not being executed when errors occur, while this worked correctly in Scrapy 2.12

### Steps to Reproduce

Spider:
```python
import scrapy


class QuotesSpider(scrapy.Spider):
    name = "quotes"

    def start_requests(self):
        urls = [
            "https://quotes.toscrape.com/page/1/",
        ]
        for url in urls:
            yield scrapy.Request(url=url, callback=self.parse, errback=self.errback)

    def errback(self, failure):
        print("errback", failure)
        yield  # <-- This works fine if it's not a generator function

    def parse(self, response):
        print(response)

```

Middleware:
```python
class TutorialDownloaderMiddleware:
    def process_request(self, request, spider):
        raise Exception("process request error")
```

**Expected behavior:** [What you expect to happen]
The errback function is called

**Actual behavior:** [What actually happens]
The errback function was not called

**Reproduces how often:** [What percentage of the time does it reproduce?]

### Versions

```
Scrapy       : 2.13.1
lxml         : 5.4.0
libxml2      : 2.13.8
cssselect    : 1.3.0
parsel       : 1.10.0
w3lib        : 2.3.1
Twisted      : 24.11.0
Python       : 3.13.4 (main, Jun  4 2025, 17:44:50) [Clang 20.1.4 ]
pyOpenSSL    : 25.1.0 (OpenSSL 3.5.0 8 Apr 2025)
cryptography : 45.0.3
Platform     : macOS-15.5-x86_64-i386-64bit-Mach-O
```
