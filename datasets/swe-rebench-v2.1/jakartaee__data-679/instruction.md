[Bug]: PageRequest doesn't know whether it's a Builder
### Specification Version

1.0.0-M3

### Bug report

`PageRequest` has multiple operations capable of producing an object in an inconsistent state. The most dangerous of these is `page(long)`, which looks harmless enough but actually results in something completely broken if you call it an a `PageRequest` with a `Cursor`. And there's no warning of this in the Javadoc, even. On the other hand, it also has operations like `next()` which are written to be called by the application.

It is in no way obvious to the user that these operations `page(long)` and `next()` are so different in nature. So much so that even I have tripped up twice over the difference and I am far from a casual user of this API.

We need to remove these dangerous operations to a `Builder`-type object, or do what I suggested a while ago, and expose the constructor of `Pagination` to Jakarta Data implementations and simply remove the "dangerous" methods. (This is the simplest solution.)

### Additional information

_No response_

### Additional contract requirements

- `PageRequest` must not expose any public method named `page` with a single `long` parameter, whether static or instance. The page number is supplied when a `PageRequest` is created (for example via `PageRequest.ofPage(long)` or the cursor factory methods) and cannot be changed on an existing instance.
