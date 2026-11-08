Unquoted param in Content-Type header is not automatically quoted
What I did:
Tried to parse a mime file with an attachment whose file name had spaces and was unquoted in the `Content-Type` header.

What I expected:
The package would quote the unquoted string before processing

What I got:
`got err mime: invalid media parameter`

Release or branch I am using:
master

(Please attach a sample message if you feel it will help reproduce the issue)

https://github.com/jhillyerd/enmime/pull/183
I created a failing test to replicated the issue on the above PR. Would be willing to submit a fix, however I am unsure if this is a case that this package is willing to cover.

Thanks for the great package!
