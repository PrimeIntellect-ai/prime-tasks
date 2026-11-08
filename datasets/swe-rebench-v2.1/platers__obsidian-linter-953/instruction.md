Bug: Wikilinks get included when moving tags to frontmatter
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

If tags in the body that have a wikilink right next to it, this will cause the wikilink to also be placed in the tags frontmatter.

## How to Reproduce

This
``` markdown
---
title: Note
Date: 2023-10-24T23:00:00+08:00
lastMod: 2023-11-28T17:36:29+08:00
---

#tag![[image.png]]
```
turns into
```markdown
---
title: Note
Date: 2023-10-24T23:00:00+08:00
lastMod: 2023-11-28T17:36:59+08:00
tags: [tag![[image.png]]]
---

#tag{WIKI_LINK_PLACEHOLDER}
```


## Expected Behavior

It shouldn't include that wikilink at all. If this is intended behavior, then an option to disable this would be nice.

```markdown
---
title: Note
Date: 2023-10-24T23:00:00+08:00
lastMod: 2023-11-28T17:36:59+08:00
tags: [tag]
---

#tag![[image.png]]
```

## Device

- [x] Desktop
- [ ] Mobile
