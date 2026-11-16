Feature: Support metadata URLs used for open graph/twitter cards
Websites can provide metadata like thumbnails/preview images using the `<meta>` tag. [Open Graph](https://ogp.me/) is used by most platforms and Twitter has its own format but they all use `<meta>` tags where the `content=` attribute can contain a URL.

My use case is that I crawl my website locally to make sure that I don't have any broken links in the meta URLs. So I would find this feature helpful.

I am happy to send a PR but wanted to check if there is interest in this feature first.

### Additional contract requirements

- A metadata URL is read from the `content` attribute of a `<meta>` tag, and the metadata property is identified by the `property` attribute.
- The supported property values are `og:image` (Open Graph image) and `twitter:image` (Twitter card image); the URL in their `content` attribute is collected as a link.
- `<meta>` tags whose `property` is not one of the supported values (for example `og:title`) contribute no links.
