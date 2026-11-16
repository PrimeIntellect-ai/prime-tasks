[Robots.txt] Handle allow/disallow directives containing unescaped Unicode characters
[Section 2.2.2 of RFC 9309](https://www.rfc-editor.org/rfc/rfc9309.html#section-2.2.2) requires that paths in allow/disallow directives are percent-encoded first:

> Octets in the URI and robots.txt paths outside the range of the ASCII coded character set, and those in the reserved range defined by [[RFC3986](https://www.rfc-editor.org/rfc/rfc9309.html#RFC3986)], MUST be percent-encoded as defined by [[RFC3986](https://www.rfc-editor.org/rfc/rfc9309.html#RFC3986)] prior to comparison.

... under the requirement that robots.txt files are UTF-8 ([section 2.3](https://www.rfc-editor.org/rfc/rfc9309.html#section-2.3)).

The reference parser includes a [unit test for the example path](https://github.com/google/robotstxt/blob/455b1583103d13ad88fe526bc058d6b9f3309215/robots_test.cc#L415) `/foo/bar/ツ` resp. `/foo/bar/%E3%83%84`.

Currently, SimpleRobotRulesParser reads the robots.txt as ASCII - Java then replaces bytes outside the ASCII range by � (U+FFFD) and also does not try to percent-encode the paths in the allow/disallow directives.
