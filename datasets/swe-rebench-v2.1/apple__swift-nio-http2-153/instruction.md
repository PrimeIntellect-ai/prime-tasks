HTTP2to1ServerCodec: should we be more tolerant with the headers the user provides
- we should probably lower-case the header names automatically
- we should probably just ignore `connection: keep-alive/close`
- we should probably drop `transfer-encoding: chunked`
