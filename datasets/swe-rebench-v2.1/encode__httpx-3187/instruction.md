Httpx is not encoding "%" symbol while sending requests
### Discussed in https://github.com/encode/httpx/discussions/3094

<div type='discussions-op-text'>

<sup>Originally posted by **heysarthak** February 14, 2024</sup>
Hi team,

I am ussing httpx plugin, while sending httpx query "ngi%abc.com" .
ideally "%" symbol should be encoded as "%25" but it is still sending as the same "%".

can we please have a fix for this.</div>

### Additional contract requirements

- For a raw URL query string (`url=`), a literal `%` that is not part of a valid
  percent-escape sequence (i.e. not followed by two hexadecimal digits) is encoded
  as `%25`, while valid percent-escape sequences are preserved unchanged.
- `str(URL)` includes the percent-encoded host, so a URL constructed from
  `"https://exam%le.com/"` renders as `"https://exam%25le.com/"`.
- When query parameters are supplied through `params={}`, literal percent signs in
  parameter values are encoded as `%25` in the rendered query string.
