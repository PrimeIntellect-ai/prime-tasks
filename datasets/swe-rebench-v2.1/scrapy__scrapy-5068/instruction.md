MediaPipeline exceptions passed silently
### Description

MediaPipeline exceptions passed silently both for method body or method signature errors.

### Steps to Reproduce

```
from scrapy.pipelines.files import FilesPipeline
class BuggyFilesPipeline(FilesPipeline):
    def file_path(self, request, response=None, info=None, *, item=None):
        return 1 / 0
```
**Expected behavior:** Exception logged

**Actual behavior:** Exception passed silently

**Reproduces how often:** 100%

### Versions

Scrapy 2.4

### Additional contract requirements

- The logged output must include the exception class name: `ZeroDivisionError` for the method-body error and `TypeError` for a method-signature error.
