FR: Rule to add newline after front matter
## Is Your Feature Request Related to a Problem? Please Describe.

For now we have option "Empty Line Between YAML and Header", but would be nice to have something like "Empty Line After YAML" which adds empty line after front matter and next node (header, paragraph, list etc), because not every note has header right after front matter.

## Describe the Solution You'd Like

Add option `Empty Line After YAML` to automatically insert new line after YAML front matter.

**Please include an example where applicable:**

``` markdown
---
tags: foo, bar
---
Hello, world!
```

``` markdown
---
tags: foo, bar
---

Hello, world!
```

## Describe Alternatives You've Considered

-

## Additional Context

-
