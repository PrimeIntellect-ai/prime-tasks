ExecuteEngine.close() assumes self.downloader has been defined
https://github.com/scrapy/scrapy/blob/8fb8d2c6b8a83181ef6564fbc9afa9cfeea2bd05/scrapy/core/engine.py#L177

However, `self.close()` is called in the `finally` block where `self.downloader` is set, so that may not be always the case.

Found it after using scrapy-poet with bad imports in a page object file consumed with `consume_modules()`.
