Serve static Brotli compressed files
### Is your feature request related to a problem?

Currently only the _aiohttp_ client supports Brotli compression, and the _aiohttp_ server is missing such capability for even just serving Brotli files that are statically compressed by the user (i.e. a file with the `.br` extension exists).

### Describe the solution you'd like

For static requests, server should look for `.br` file extension in addition to `.gz`, and prefer Brotli over GZip if both exist.

I will submit a PR shortly for this.  I opened the issue as a formality.

### Describe alternatives you've considered

None

### Related component

Server

### Additional context

#2518 is obviously a similar feature request, but this request focuses on just starting with precompressed Brotli capability, and then expanding to dynamic compression.

### Code of Conduct

- [X] I agree to follow the aio-libs Code of Conduct
