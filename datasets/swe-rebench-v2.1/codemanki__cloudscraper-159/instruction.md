Email protection is not parsed by cloudscraper
On Crunchyroll, they have activated the "email protection" from cloudflare and when I try to scrape some of their webpages I get "[email protected]" instead of the expected text.

Example: http://www.crunchyroll.com/the-idolmster-cinderella-girls-theater#

On that webpage the "DOLM@STER" is seen as an email by cloudflare (that mean their regexp is fabulously wrong) and it screw my scraping because I'm not expecting ton of the javascript they insert for that "protection".

It would be nice if cloudscraper could detect these insertion and parse them the same as it does for the browser detection.

### Additional contract requirements

- Cloudscraper must offer the `decodeEmails` option. When it is enabled, successful response bodies containing Cloudflare email-protection markup must expose the intended plain-text email address instead of the protected representation, both to the callback and through the returned promise. Email decoding must remain disabled by default.
