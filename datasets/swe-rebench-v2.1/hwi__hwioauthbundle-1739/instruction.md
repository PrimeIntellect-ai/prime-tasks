Expired token does not refresh
Hi,

After the commit below, the expired token is never refreshed.

https://github.com/hwi/HWIOAuthBundle/commit/07832663737521d932416626fdc08ca3ca34f17c#diff-b6dd8e26135237df333dee640dafed3c7821bbb728e868df0e251cce60084a88

The suggested solution is to check if the token is still valid.

[HIDDEN]

### Additional contract requirements

- An expired token must not be returned as an authenticated token; it must proceed to the refresh logic.
