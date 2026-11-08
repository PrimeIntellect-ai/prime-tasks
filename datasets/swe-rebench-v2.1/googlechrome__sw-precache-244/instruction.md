Apply dontCacheBustUrlsMatching to the pathname
Moved from https://github.com/jeffposnick/create-react-pwa/issues/14

Right now the `dontCacheBustUrlsMatching` parameter, if set, is matched against the full URL. It should only match against the URL's `pathname`, to prevent false-positives if the origin portion of the URL matches.

CC: @bgrzys
