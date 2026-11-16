feature: atom: handle xml:base attribute on content
atom content element define a optional xml:base attribute to `establishing the base URI (or IRI) for resolving any relative references found within the effective scope of the xml:base
   attribute.` from [rfc4287 section 2](https://datatracker.ietf.org/doc/html/rfc4287#section-2)

would you find acceptable to add a optional `base` field to [Entry](https://github.com/feed-rs/feed-rs/blob/890aeadc508c9228bcc01e25f0f861e32a68e741/feed-rs/src/model.rs#L233) ?

### Additional contract requirements

- In the `feed_rs::model` module, `Entry` has a public field `base: Option<String>` that holds the base URI extracted from the feed, or `None` when no base URI is present.
- `Entry` has a public builder method `base(self, url: &str) -> Entry` that returns the entry with its base URI set to `url`, so it can be used in a method chain.
