Make multipart forms resilient to path traversal attacks
See https://tools.ietf.org/html/rfc7578:

> If a "filename" parameter is supplied, the requirements of
> Section 2.3 of [RFC2183] for the "receiving MUA" (i.e., the receiving
> Mail User Agent) apply to receivers of multipart/form-data as well:
> do not use the file name blindly, check and possibly change to match
> local file system conventions if applicable, and do not use directory
> path information that may be present.
