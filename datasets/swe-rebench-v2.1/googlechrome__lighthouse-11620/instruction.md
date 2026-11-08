Incorrect main document used when retrieving page load errors
<!-- Before creating an issue please make sure you are using the latest version and have checked for duplicate issues. -->

#### Provide the steps to reproduce
1. Run LH programmatically on page that redirects a similarly matching URL (e.g. same `startsWith(request.url)`), where the redirect response does not return `text/html` as its mime type.

_More Information_

I'm not sure how common this for non-authenticated redirects, but in our case we are running LH on authenticated pages using cookie-based login (similar to [this doc](https://github.com/GoogleChrome/lighthouse/blob/master/docs/authenticated-pages.md#option-3-pass-custom-request-headers-with-lighthouse-cli), but with Node API).

The redirect response when hitting the requestedUrl (prior to auth) does not return HTML, and so the content-type response header is empty. It then redirects to the authentication server, and finally back to the originally requested document this time with the correct mime type `text/html`.

<!-- If your page is only local, or is liable to change, consider uploading a repro so that we can more easily debug the problem. Some services that will help are: https://jsbin.com/, https://surge.sh/ -->

#### What is the current behavior?

LH reports error `NOT_HTML` even though document loaded in the final URL after redirecting is `text/html`.

I don't see any documentation on this, but according @brendankenny in #11430, it should be the final matching URL (that is an html document) when loading the page.

The error occurred starting in version 6.2.0 of LH from #11042.

[HIDDEN]

As for the logic when `finalUrl` is not supplied, I think the comment on line 452 still applies.

#### What is the expected behavior?

LH doesn't fail when valid redirect eventually responds with HTML on a matching `finalUrl`.

#### Environment Information
* Affected Channels: Node
* Lighthouse version: >=6.2.0
* Chrome version: N/A
* Node.js version: 12.9.2
* Operating System: MacOS (and Docker Linux Container)

**Related issues**
* #11042
* #11430

### Additional contract requirements

- For a redirecting navigation, page-load HTML validity must reflect the document ultimately loaded: an earlier non-HTML redirect response must not cause `NOT_HTML` when the final document is `text/html`.
