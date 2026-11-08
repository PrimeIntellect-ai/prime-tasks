ES module compatible export
It would be useful to make svgo compatible with ES module interop tools, so that downstream libraries that depend on svgo can also provide an ES module distribution.

I think the simplest approach here would be to [HIDDEN]

### Additional contract requirements

- The module’s `default` export must refer to the same constructor as its existing `SVGO` export.
