Deduplicate tags after merging
**Is your feature request related to a problem? Please describe.**
When I'm generating a collection on my site, I sometimes use data merging to provide tags common to the series and then tag individual posts further. If I happen to forget that I already have a tag for a given collection, I end up with duplicate tags. This isn't terrible, but it can easily mean that I have duplicates in the JSON Feed I generate.

**Describe the solution you'd like**
Tags (and indeed data in general) should be deduplicated; at a minimum it should be *possible* to deduplicate.

**Describe alternatives you've considered**
- Just keep manually making sure to avoid duplicates
- Deduplicate manually anywhere the collection is used

**Additional context**
N/A

### Additional contract requirements

- When a page's data is merged from several sources (for example, a directory data file and the template's front matter) and the same tag is provided more than once, the page's `tags` list must contain that tag only once. This deduplication applies by default, without any configuration change.
