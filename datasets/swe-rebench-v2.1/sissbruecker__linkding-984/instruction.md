[New feature] Add a link to public RSS from public bookmarks page
Hello! This is my first issue.

I recently set up a public page with shared bookmarks and invited friends to follow my public RSS, but then I realized that the public RSS URL is only available in settings. I think it should be possible for a user looking at a public bookmarks page to discover the RSS link.

How about adding a `<link rel="alternate" type="application/rss+xml"` to the public bookmarks page if one is available? A RSS icon somewhere in page body would also help with discoverability.

I'm assuming that the public bookmarks page and public bookmarks RSS are always both enabled or both disabled. Does that sound correct?

(I might take a stab at adding it next week if it sounds ok? maybe good first commit for me?)

### Additional contract requirements

- The link's `href` must equal `reverse("bookmarks:feeds.public_shared")`.
