Maintainer URL not being propagated to IG JSON contact URL
The IG Exporter converts maintainers in the `package.json` to contacts in the ImplementationGuide JSON.  While it successfully converts name and email, it seems to drop url.  This means we can't supply contact URLs, which affects the link to the publisher in the footer of the rendered IG.

### Additional contract requirements

- A maintainer entry in the SUSHI configuration (`package.json`) carries a `url` field holding the maintainer's web presence URL.
- The generated ImplementationGuide JSON represents each maintainer as a `contact`. When a maintainer's `url` is present, that contact's `telecom` array includes an entry with `system` `'url'` and `value` equal to the maintainer's `url`; when a maintainer has no `url`, no such entry is produced.
- When a maintainer also has an `email`, the contact's `telecom` array includes both the `url` entry and the `email` entry, with the `url` entry appearing before the `email` entry.
