[BasicNormalizer] decode percent-encoded host names
BasicURLNormalizer should decode percent-encoded characters in host names, similar as done by web browsers. Examples: https://example%2Ecom/ or https://www.0251-sachverst%c3%a4ndiger.de/, see also [NUTCH-2824](https://issues.apache.org/jira/browse/NUTCH-2824).
