Older versions of mxPoint do not decode successfully
The codec registration method is compatible with mxCell, mxGeometry, and mxGraphModel, but is not compatible with mxPoint.

  // mxGraph support
        CodecRegistry.addAlias('mxGraphModel', 'GraphDataModel');
        CodecRegistry.register(new mxCellCodec(), false);
        CodecRegistry.register(new mxGeometryCodec(), false);

Does it need to add compatibility support for mxPoint?like fellows：
// decode support for mxPoint
[HIDDEN]

### Additional contract requirements

- Decoding legacy `mxPoint` elements must produce current `Point` values and preserve their data when used as geometry offsets.
